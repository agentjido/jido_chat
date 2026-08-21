defmodule Jido.Chat.StateAdapters.Memory do
  @moduledoc """
  Default in-memory state adapter.

  This preserves the current pure-struct semantics while routing all state access
  through the `Jido.Chat.StateAdapter` contract.
  """

  @behaviour Jido.Chat.StateAdapter

  alias Jido.Chat.{Concurrency, StateAdapter}

  @max_concurrency_events 100

  @enforce_keys [:subscriptions, :dedupe, :dedupe_order, :thread_state, :channel_state]
  defstruct subscriptions: MapSet.new(),
            dedupe: MapSet.new(),
            dedupe_order: [],
            thread_state: %{},
            channel_state: %{},
            locks: %{},
            pending_locks: %{},
            concurrency_events: []

  @type t :: %__MODULE__{
          subscriptions: MapSet.t(String.t()),
          dedupe: MapSet.t(StateAdapter.dedupe_key()),
          dedupe_order: [StateAdapter.dedupe_key()],
          thread_state: %{optional(String.t()) => map()},
          channel_state: %{optional(String.t()) => map()},
          locks: %{optional(String.t()) => map()},
          pending_locks: %{optional(String.t()) => [map()]},
          concurrency_events: [map()]
        }

  @impl true
  def init(snapshot, _opts \\ []) do
    snapshot = StateAdapter.normalize_snapshot(snapshot)

    %__MODULE__{
      subscriptions: snapshot.subscriptions,
      dedupe: snapshot.dedupe,
      dedupe_order: snapshot.dedupe_order,
      thread_state: snapshot.thread_state,
      channel_state: snapshot.channel_state,
      locks: snapshot.locks,
      pending_locks: snapshot.pending_locks,
      concurrency_events: snapshot.concurrency_events
    }
  end

  @impl true
  def snapshot(%__MODULE__{} = state) do
    %{
      subscriptions: state.subscriptions,
      dedupe: state.dedupe,
      dedupe_order: state.dedupe_order,
      thread_state: state.thread_state,
      channel_state: state.channel_state,
      locks: state.locks,
      pending_locks: state.pending_locks,
      concurrency_events: state.concurrency_events
    }
  end

  @impl true
  def subscribed?(%__MODULE__{} = state, thread_id),
    do: MapSet.member?(state.subscriptions, thread_id)

  @impl true
  def subscribe(%__MODULE__{} = state, thread_id) do
    %{state | subscriptions: MapSet.put(state.subscriptions, thread_id)}
  end

  @impl true
  def unsubscribe(%__MODULE__{} = state, thread_id) do
    %{state | subscriptions: MapSet.delete(state.subscriptions, thread_id)}
  end

  @impl true
  def thread_state(%__MODULE__{} = state, thread_id),
    do: Map.get(state.thread_state, thread_id, %{})

  @impl true
  def put_thread_state(%__MODULE__{} = state, thread_id, value) when is_map(value) do
    %{state | thread_state: Map.put(state.thread_state, thread_id, value)}
  end

  @impl true
  def channel_state(%__MODULE__{} = state, channel_id),
    do: Map.get(state.channel_state, channel_id, %{})

  @impl true
  def put_channel_state(%__MODULE__{} = state, channel_id, value) when is_map(value) do
    %{state | channel_state: Map.put(state.channel_state, channel_id, value)}
  end

  @impl true
  def duplicate?(%__MODULE__{} = state, key), do: MapSet.member?(state.dedupe, key)

  @impl true
  def mark_dedupe(%__MODULE__{} = state, key, dedupe_limit)
      when is_tuple(key) and is_integer(dedupe_limit) and dedupe_limit > 0 do
    dedupe = MapSet.put(state.dedupe, key)
    dedupe_order = state.dedupe_order ++ [key]

    {trimmed_dedupe_order, overflow_keys} = trim_dedupe_order(dedupe_order, dedupe_limit)

    trimmed_dedupe =
      Enum.reduce(overflow_keys, dedupe, fn overflow_key, acc ->
        MapSet.delete(acc, overflow_key)
      end)

    %{state | dedupe: trimmed_dedupe, dedupe_order: trimmed_dedupe_order}
  end

  @impl true
  def lock(%__MODULE__{} = state, key, owner, strategy, metadata) do
    lock_with_options(state, key, owner, strategy, metadata, %{})
  end

  @impl true
  def lock_with_options(%__MODULE__{} = state, key, owner, strategy, metadata, options) do
    {config, now_ms, conversation_key} = lock_input(strategy, key, options)

    case strategy do
      :concurrent ->
        lock_concurrent(state, key, owner, config, metadata)

      strategy when strategy in [:reject, :queue, :debounce, :burst] ->
        lock_serial(state, key, owner, strategy, metadata, config, now_ms, conversation_key)
    end
  end

  @impl true
  def release_lock(%__MODULE__{} = state, key, owner) do
    release_lock_with_options(state, key, owner, System.system_time(:millisecond))
  end

  @impl true
  def release_lock_with_options(%__MODULE__{} = state, key, owner, now_ms) do
    case Map.get(state.locks, key) do
      %{owner: ^owner} ->
        {state, pending} = expire_pending(state, key, now_ms)

        next_state =
          state
          |> delete_lock(key)
          |> delete_pending(key)

        {{:released, pending}, next_state}

      %{strategy: :concurrent, owners: owners} = lock ->
        if owner in owners do
          remaining = List.delete(owners, owner)

          next_state =
            if remaining == [] do
              delete_lock(state, key)
            else
              %{state | locks: Map.put(state.locks, key, %{lock | owners: remaining})}
            end

          {{:released, []}, next_state}
        else
          {{:error, :not_owner}, state}
        end

      _other ->
        {{:error, :not_owner}, state}
    end
  end

  @impl true
  def force_release_lock(%__MODULE__{} = state, key) do
    pending = Map.get(state.pending_locks, key, [])

    next_state =
      state
      |> delete_lock(key)
      |> delete_pending(key)

    {{:released, pending}, next_state}
  end

  @impl true
  def drain_lock(%__MODULE__{} = state, key, owner, now_ms, conversation_key) do
    case Map.get(state.locks, key) do
      %{owner: ^owner} = lock ->
        drain_owned_lock(state, key, lock, now_ms, conversation_key)

      _other ->
        {{:error, :not_owner}, state}
    end
  end

  defp trim_dedupe_order(dedupe_order, dedupe_limit) do
    overflow_count = max(length(dedupe_order) - dedupe_limit, 0)

    if overflow_count == 0 do
      {dedupe_order, []}
    else
      {overflow_keys, remaining_keys} = Enum.split(dedupe_order, overflow_count)
      {remaining_keys, overflow_keys}
    end
  end

  defp put_lock(%__MODULE__{} = state, key, owner, strategy, metadata, attrs) do
    lock = Map.merge(%{owner: owner, strategy: strategy, metadata: metadata}, attrs)
    %{state | locks: Map.put(state.locks, key, lock)}
  end

  defp delete_lock(%__MODULE__{} = state, key), do: %{state | locks: Map.delete(state.locks, key)}

  defp delete_pending(%__MODULE__{} = state, key),
    do: %{state | pending_locks: Map.delete(state.pending_locks, key)}

  defp pending_entry(owner, strategy, metadata, now_ms, config, conversation_key) do
    %{
      owner: owner,
      strategy: strategy,
      metadata: metadata,
      enqueued_at: now_ms,
      expires_at: now_ms + config.queue_entry_ttl_ms,
      ready_at: pending_ready_at(strategy, now_ms, config.debounce_ms),
      conversation_key: conversation_key
    }
  end

  defp pending_ready_at(strategy, now_ms, debounce_ms) when strategy in [:burst, :debounce],
    do: now_ms + debounce_ms

  defp pending_ready_at(_strategy, now_ms, _debounce_ms), do: now_ms

  defp lock_input(strategy, key, options) do
    config = options[:config] || options["config"] || %{strategy: strategy}
    config = if match?(%Concurrency{}, config), do: config, else: Concurrency.new(config)
    now_ms = options[:now_ms] || options["now_ms"] || System.system_time(:millisecond)

    conversation_key =
      options[:conversation_key] || options["conversation_key"] || key

    {config, now_ms, conversation_key}
  end

  defp lock_concurrent(state, _key, _owner, %Concurrency{max_concurrent: nil}, _metadata),
    do: {:acquired, state}

  defp lock_concurrent(state, key, owner, %Concurrency{max_concurrent: maximum}, metadata) do
    case Map.get(state.locks, key) do
      nil ->
        lock = %{
          owner: owner,
          owners: [owner],
          strategy: :concurrent,
          max_concurrent: maximum,
          metadata: metadata
        }

        {:acquired, %{state | locks: Map.put(state.locks, key, lock)}}

      %{strategy: :concurrent, owners: owners} = lock when length(owners) < maximum ->
        next_lock = %{lock | owners: owners ++ [owner]}
        {:acquired, %{state | locks: Map.put(state.locks, key, next_lock)}}

      _lock ->
        {:busy, state}
    end
  end

  defp lock_serial(state, key, owner, strategy, metadata, config, now_ms, conversation_key) do
    case Map.get(state.locks, key) do
      nil when strategy == :burst ->
        state =
          put_lock(state, key, owner, strategy, metadata, %{
            ready_at: now_ms + config.debounce_ms,
            conversation_key: conversation_key
          })

        enqueue_bounded(state, key, owner, strategy, metadata, config, now_ms, conversation_key, first?: true)

      nil ->
        {:acquired, put_lock(state, key, owner, strategy, metadata, %{conversation_key: conversation_key})}

      _lock when strategy == :reject ->
        event = %{
          event: :dropped,
          key: key,
          lock_key: key,
          owner: owner,
          strategy: :reject,
          at: now_ms,
          reason: :lock_busy,
          message_id: event_message_id(%{metadata: metadata}),
          conversation_key: conversation_key
        }

        {:busy, record_event(state, event)}

      _lock when strategy in [:queue, :burst] ->
        enqueue_bounded(state, key, owner, strategy, metadata, config, now_ms, conversation_key)

      lock when strategy == :debounce ->
        debounce(state, key, lock, owner, metadata, config, now_ms, conversation_key)
    end
  end

  defp enqueue_bounded(
         state,
         key,
         owner,
         strategy,
         metadata,
         config,
         now_ms,
         conversation_key,
         opts \\ []
       ) do
    {state, pending} = expire_pending(state, key, now_ms)
    entry = pending_entry(owner, strategy, metadata, now_ms, config, conversation_key)
    first? = Keyword.get(opts, :first?, false)

    cond do
      length(pending) < config.max_queue_size ->
        accepted = pending ++ [entry]

        state =
          state
          |> put_pending(key, accepted)
          |> refresh_active_deadline(key, entry)

        state = record_event(state, queue_event(key, entry, length(pending) + 1))
        {if(first?, do: :bursting, else: :queued), state}

      config.overflow_policy == :drop_newest ->
        state = record_event(state, dropped_event(key, entry, :drop_newest))
        {:dropped, state}

      true ->
        [oldest | remaining] = pending

        state =
          state
          |> put_pending(key, remaining ++ [entry])
          |> refresh_active_deadline(key, entry)
          |> record_event(dropped_event(key, oldest, :drop_oldest))
          |> record_event(queue_event(key, entry, config.max_queue_size))

        {if(first?, do: :bursting, else: :queued), state}
    end
  end

  defp debounce(state, key, lock, owner, metadata, config, now_ms, conversation_key) do
    {state, pending} = expire_pending(state, key, now_ms)
    entry = pending_entry(owner, :debounce, metadata, now_ms, config, conversation_key)
    {replaced, retained} = split_conversation(pending, conversation_key, key)

    state =
      Enum.reduce(replaced, state, fn superseded, acc ->
        record_event(acc, superseded_event(key, superseded, owner, now_ms))
      end)

    next_lock =
      if lock_conversation(lock, key) == conversation_key do
        Map.put(lock, :ready_at, entry.ready_at)
      else
        lock
      end

    state =
      state
      |> put_pending(key, retained ++ [entry])
      |> then(&%{&1 | locks: Map.put(&1.locks, key, next_lock)})
      |> record_event(queue_event(key, entry, 1))

    {:debounced, state}
  end

  defp drain_owned_lock(state, key, lock, now_ms, conversation_key) do
    {state, pending} = expire_pending(state, key, now_ms)
    {selected, retained} = split_conversation(pending, conversation_key, key)
    ready_at = conversation_ready_at(selected, lock)

    if ready_at > now_ms do
      {{:waiting, %{remaining_ms: ready_at - now_ms}}, state}
    else
      drain_conversation(state, key, lock, selected, retained, now_ms, conversation_key)
    end
  end

  defp drain_conversation(state, key, lock, selected, retained, now_ms, conversation_key) do
    strategy = lock[:strategy] || :queue

    {latest, skipped} = select_dispatch(selected, strategy)
    dispatch = build_dispatch(latest, skipped)

    drained_event = %{
      event: :drained,
      key: key,
      lock_key: key,
      owner: latest && latest.owner,
      message_id: latest && event_message_id(latest),
      strategy: strategy,
      at: now_ms,
      skipped_count: length(skipped),
      total_count: if(latest, do: length(skipped) + 1, else: 0),
      drained_count: length(selected),
      conversation_key: conversation_key
    }

    next_state =
      state
      |> put_pending(key, retained)
      |> promote_retained_lock(key, retained)
      |> record_event(drained_event)

    {{:drained, dispatch}, next_state}
  end

  defp select_dispatch([], _strategy), do: {nil, []}

  defp select_dispatch(pending, strategy) do
    latest = List.last(pending)

    skipped =
      if strategy == :debounce do
        []
      else
        Enum.drop(pending, -1)
      end

    {latest, skipped}
  end

  defp build_dispatch(nil, _skipped), do: nil

  defp build_dispatch(latest, skipped) do
    Map.put(latest, :context, Concurrency.message_context(skipped))
  end

  defp expire_pending(state, key, now_ms) do
    pending = Map.get(state.pending_locks, key, [])

    {expired, active} =
      Enum.split_with(pending, fn entry ->
        expires_at = entry[:expires_at] || entry["expires_at"]
        is_integer(expires_at) and expires_at < now_ms
      end)

    state =
      Enum.reduce(expired, state, fn entry, acc ->
        record_event(acc, expired_event(key, entry, now_ms))
      end)

    {put_pending(state, key, active), active}
  end

  defp split_conversation(pending, conversation_key, fallback_conversation_key) do
    Enum.split_with(pending, fn entry ->
      entry_conversation(entry, fallback_conversation_key) == conversation_key
    end)
  end

  defp entry_conversation(entry, fallback),
    do: entry[:conversation_key] || entry["conversation_key"] || fallback

  defp lock_conversation(lock, fallback),
    do: lock[:conversation_key] || lock["conversation_key"] || fallback

  defp conversation_ready_at([], lock), do: lock[:ready_at] || lock["ready_at"] || 0

  defp conversation_ready_at(entries, lock) do
    latest = List.last(entries)
    latest[:ready_at] || latest["ready_at"] || lock[:ready_at] || lock["ready_at"] || 0
  end

  defp refresh_active_deadline(state, key, %{strategy: :burst} = entry) do
    case Map.get(state.locks, key) do
      nil ->
        state

      lock ->
        if lock_conversation(lock, key) == entry.conversation_key do
          next_lock = Map.put(lock, :ready_at, entry.ready_at)
          %{state | locks: Map.put(state.locks, key, next_lock)}
        else
          state
        end
    end
  end

  defp refresh_active_deadline(state, _key, _entry), do: state

  defp promote_retained_lock(state, key, []), do: delete_lock(state, key)

  defp promote_retained_lock(state, key, [first | _] = retained) do
    conversation_key = entry_conversation(first, key)

    conversation_entries =
      Enum.filter(retained, fn entry -> entry_conversation(entry, key) == conversation_key end)

    latest = List.last(conversation_entries)

    lock = %{
      owner: first[:owner] || first["owner"],
      strategy: first[:strategy] || first["strategy"],
      metadata: first[:metadata] || first["metadata"] || %{},
      ready_at: latest[:ready_at] || latest["ready_at"] || 0,
      conversation_key: conversation_key
    }

    %{state | locks: Map.put(state.locks, key, lock)}
  end

  defp put_pending(state, key, []),
    do: %{state | pending_locks: Map.delete(state.pending_locks, key)}

  defp put_pending(state, key, pending),
    do: %{state | pending_locks: Map.put(state.pending_locks, key, pending)}

  defp record_event(state, event),
    do: %{
      state
      | concurrency_events: (state.concurrency_events ++ [event]) |> Enum.take(-@max_concurrency_events)
    }

  defp queue_event(key, entry, depth) do
    %{
      event: :queued,
      key: key,
      lock_key: key,
      owner: entry.owner,
      strategy: entry.strategy,
      at: entry.enqueued_at,
      message_id: event_message_id(entry),
      queue_depth: depth,
      conversation_key: entry.conversation_key
    }
  end

  defp dropped_event(key, entry, policy) do
    %{
      event: :dropped,
      key: key,
      lock_key: key,
      owner: entry.owner,
      strategy: entry.strategy,
      at: entry.enqueued_at,
      message_id: event_message_id(entry),
      reason: :queue_full,
      overflow_policy: policy,
      conversation_key: entry.conversation_key
    }
  end

  defp expired_event(key, entry, now_ms) do
    %{
      event: :expired,
      key: key,
      lock_key: key,
      owner: entry.owner,
      strategy: entry.strategy,
      at: now_ms,
      message_id: event_message_id(entry),
      expired_at: entry.expires_at,
      conversation_key: entry.conversation_key
    }
  end

  defp superseded_event(key, entry, replacing_owner, now_ms) do
    %{
      event: :superseded,
      key: key,
      lock_key: key,
      owner: entry.owner,
      superseded_by: replacing_owner,
      strategy: :debounce,
      at: now_ms,
      message_id: event_message_id(entry),
      conversation_key: entry.conversation_key
    }
  end

  defp event_message_id(entry) do
    metadata = entry[:metadata] || entry["metadata"] || %{}
    message = metadata[:message] || metadata["message"] || metadata[:incoming] || metadata["incoming"]

    get_value(message, :id) || get_value(message, :external_message_id) ||
      get_value(metadata, :message_id)
  end

  defp get_value(%_{} = struct, key), do: Map.get(struct, key)
  defp get_value(map, key) when is_map(map), do: map[key] || map[Atom.to_string(key)]
  defp get_value(_value, _key), do: nil
end
