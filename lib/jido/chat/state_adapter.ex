defmodule Jido.Chat.StateAdapter do
  @moduledoc """
  Behavior and helpers for pluggable chat state storage.

  State adapters own subscriptions, dedupe windows, and per-thread / per-channel
  state maps. The default adapter keeps everything in memory, but adapters may
  persist state elsewhere as long as they can expose a normalized snapshot.
  """

  @type dedupe_key :: {atom(), String.t()}

  @type snapshot :: %{
          subscriptions: MapSet.t(String.t()),
          dedupe: MapSet.t(dedupe_key()),
          dedupe_order: [dedupe_key()],
          thread_state: %{optional(String.t()) => map()},
          channel_state: %{optional(String.t()) => map()},
          locks: %{optional(String.t()) => map()},
          pending_locks: %{optional(String.t()) => [map()]},
          concurrency_events: [map()]
        }

  @type state :: term()
  @type lock_result :: :acquired | :queued | :debounced | :bursting | :dropped | :busy
  @type release_result :: {:released, [map()]} | {:error, :not_owner}
  @type drain_result ::
          {:drained, map() | nil}
          | {:waiting, %{remaining_ms: non_neg_integer()}}
          | {:error, :not_owner}

  @callback init(snapshot(), keyword()) :: state()
  @callback snapshot(state()) :: snapshot() | map()
  @callback subscribed?(state(), String.t()) :: boolean()
  @callback subscribe(state(), String.t()) :: state()
  @callback unsubscribe(state(), String.t()) :: state()
  @callback thread_state(state(), String.t()) :: map()
  @callback put_thread_state(state(), String.t(), map()) :: state()
  @callback channel_state(state(), String.t()) :: map()
  @callback put_channel_state(state(), String.t(), map()) :: state()
  @callback duplicate?(state(), dedupe_key()) :: boolean()
  @callback mark_dedupe(state(), dedupe_key(), pos_integer()) :: state()
  @callback lock(state(), String.t(), String.t(), atom(), map()) :: {lock_result(), state()}
  @callback lock_with_options(state(), String.t(), String.t(), atom(), map(), map()) ::
              {lock_result(), state()}
  @callback release_lock(state(), String.t(), String.t()) :: {release_result(), state()}
  @callback release_lock_with_options(state(), String.t(), String.t(), non_neg_integer()) ::
              {release_result(), state()}
  @callback force_release_lock(state(), String.t()) :: {{:released, [map()]}, state()}
  @callback drain_lock(state(), String.t(), String.t(), non_neg_integer(), String.t()) ::
              {drain_result(), state()}

  @optional_callbacks drain_lock: 5, lock_with_options: 6, release_lock_with_options: 4

  @dialyzer {:nowarn_function, default_snapshot: 0}

  @doc "Initializes adapter state from a normalized snapshot."
  @spec init(module(), map(), keyword()) :: state()
  def init(adapter_module, snapshot, opts \\ []) when is_atom(adapter_module) do
    adapter_module.init(normalize_snapshot(snapshot), opts)
  end

  @doc "Returns a normalized snapshot for adapter-managed state."
  @spec snapshot(module(), state()) :: snapshot()
  def snapshot(adapter_module, state) when is_atom(adapter_module) do
    adapter_module.snapshot(state)
    |> normalize_snapshot()
  end

  @doc "Returns true when the thread is subscribed in adapter-managed state."
  @spec subscribed?(module(), state(), String.t()) :: boolean()
  def subscribed?(adapter_module, state, thread_id)
      when is_atom(adapter_module) and is_binary(thread_id) do
    adapter_module.subscribed?(state, thread_id)
  end

  @doc "Adds a subscribed thread id to adapter-managed state."
  @spec subscribe(module(), state(), String.t()) :: state()
  def subscribe(adapter_module, state, thread_id)
      when is_atom(adapter_module) and is_binary(thread_id) do
    adapter_module.subscribe(state, thread_id)
  end

  @doc "Removes a subscribed thread id from adapter-managed state."
  @spec unsubscribe(module(), state(), String.t()) :: state()
  def unsubscribe(adapter_module, state, thread_id)
      when is_atom(adapter_module) and is_binary(thread_id) do
    adapter_module.unsubscribe(state, thread_id)
  end

  @doc "Returns thread state map from adapter-managed state."
  @spec thread_state(module(), state(), String.t()) :: map()
  def thread_state(adapter_module, state, thread_id)
      when is_atom(adapter_module) and is_binary(thread_id) do
    adapter_module.thread_state(state, thread_id)
  end

  @doc "Writes thread state map into adapter-managed state."
  @spec put_thread_state(module(), state(), String.t(), map()) :: state()
  def put_thread_state(adapter_module, state, thread_id, value)
      when is_atom(adapter_module) and is_binary(thread_id) and is_map(value) do
    adapter_module.put_thread_state(state, thread_id, value)
  end

  @doc "Returns channel state map from adapter-managed state."
  @spec channel_state(module(), state(), String.t()) :: map()
  def channel_state(adapter_module, state, channel_id)
      when is_atom(adapter_module) and is_binary(channel_id) do
    adapter_module.channel_state(state, channel_id)
  end

  @doc "Writes channel state map into adapter-managed state."
  @spec put_channel_state(module(), state(), String.t(), map()) :: state()
  def put_channel_state(adapter_module, state, channel_id, value)
      when is_atom(adapter_module) and is_binary(channel_id) and is_map(value) do
    adapter_module.put_channel_state(state, channel_id, value)
  end

  @doc "Returns true when a message dedupe key has already been seen."
  @spec duplicate?(module(), state(), dedupe_key()) :: boolean()
  def duplicate?(adapter_module, state, key)
      when is_atom(adapter_module) and is_tuple(key) do
    adapter_module.duplicate?(state, key)
  end

  @doc "Records a new dedupe key and trims state to the requested limit."
  @spec mark_dedupe(module(), state(), dedupe_key(), pos_integer()) :: state()
  def mark_dedupe(adapter_module, state, key, limit)
      when is_atom(adapter_module) and is_tuple(key) and is_integer(limit) and limit > 0 do
    adapter_module.mark_dedupe(state, key, limit)
  end

  @doc "Attempts to acquire a concurrency lock for the given key and owner."
  @spec lock(module(), state(), String.t(), String.t(), atom(), map()) :: {lock_result(), state()}
  def lock(adapter_module, state, key, owner, strategy, metadata \\ %{})
      when is_atom(adapter_module) and is_binary(key) and is_binary(owner) and is_atom(strategy) and
             is_map(metadata) do
    adapter_module.lock(state, key, owner, strategy, metadata)
  end

  @doc "Attempts to acquire a lock with optional bounded-concurrency controls."
  @spec lock(module(), state(), String.t(), String.t(), atom(), map(), map()) ::
          {lock_result(), state()}
  def lock(adapter_module, state, key, owner, strategy, metadata, options)
      when is_atom(adapter_module) and is_binary(key) and is_binary(owner) and is_atom(strategy) and
             is_map(metadata) and is_map(options) do
    if function_exported?(adapter_module, :lock_with_options, 6) do
      adapter_module.lock_with_options(state, key, owner, strategy, metadata, options)
    else
      adapter_module.lock(state, key, owner, strategy, metadata)
    end
  end

  @doc "Releases a held lock and returns any queued/debounced pending entries."
  @spec release_lock(module(), state(), String.t(), String.t()) :: {release_result(), state()}
  def release_lock(adapter_module, state, key, owner)
      when is_atom(adapter_module) and is_binary(key) and is_binary(owner) do
    adapter_module.release_lock(state, key, owner)
  end

  @doc "Releases a held lock and filters expired entries at the supplied time."
  @spec release_lock(module(), state(), String.t(), String.t(), non_neg_integer()) ::
          {release_result(), state()}
  def release_lock(adapter_module, state, key, owner, now_ms)
      when is_atom(adapter_module) and is_binary(key) and is_binary(owner) and
             is_integer(now_ms) and now_ms >= 0 do
    if function_exported?(adapter_module, :release_lock_with_options, 4) do
      adapter_module.release_lock_with_options(state, key, owner, now_ms)
    else
      filter_released_entries(adapter_module.release_lock(state, key, owner), now_ms)
    end
  end

  @doc "Force-releases a lock regardless of owner and returns pending entries."
  @spec force_release_lock(module(), state(), String.t()) :: {{:released, [map()]}, state()}
  def force_release_lock(adapter_module, state, key)
      when is_atom(adapter_module) and is_binary(key) do
    adapter_module.force_release_lock(state, key)
  end

  @doc "Drains a due lock into one dispatch entry with ordered message context."
  @spec drain_lock(module(), state(), String.t(), String.t(), non_neg_integer(), String.t()) ::
          {drain_result(), state()}
  def drain_lock(adapter_module, state, key, owner, now_ms, conversation_key)
      when is_atom(adapter_module) and is_binary(key) and is_binary(owner) and
             is_integer(now_ms) and now_ms >= 0 and is_binary(conversation_key) do
    if function_exported?(adapter_module, :drain_lock, 5) do
      adapter_module.drain_lock(state, key, owner, now_ms, conversation_key)
    else
      fallback_drain(adapter_module, state, key, owner, now_ms, conversation_key)
    end
  end

  @doc "Returns the canonical empty snapshot."
  @spec default_snapshot() :: snapshot()
  def default_snapshot do
    %{
      subscriptions: MapSet.new(),
      dedupe: MapSet.new(),
      dedupe_order: [],
      thread_state: %{},
      channel_state: %{},
      locks: %{},
      pending_locks: %{},
      concurrency_events: []
    }
  end

  @doc "Normalizes maps, lists, and map-sets into the canonical state snapshot shape."
  @spec normalize_snapshot(map()) :: snapshot()
  def normalize_snapshot(snapshot) when is_map(snapshot) do
    defaults = default_snapshot()

    %{
      subscriptions: snapshot[:subscriptions] || snapshot["subscriptions"] || defaults.subscriptions,
      dedupe: snapshot[:dedupe] || snapshot["dedupe"] || defaults.dedupe,
      dedupe_order: snapshot[:dedupe_order] || snapshot["dedupe_order"] || defaults.dedupe_order,
      thread_state: snapshot[:thread_state] || snapshot["thread_state"] || defaults.thread_state,
      channel_state: snapshot[:channel_state] || snapshot["channel_state"] || defaults.channel_state,
      locks: snapshot[:locks] || snapshot["locks"] || defaults.locks,
      pending_locks: snapshot[:pending_locks] || snapshot["pending_locks"] || defaults.pending_locks,
      concurrency_events:
        snapshot[:concurrency_events] || snapshot["concurrency_events"] ||
          defaults.concurrency_events
    }
    |> normalize_subscriptions()
    |> normalize_dedupe()
    |> normalize_dedupe_order()
    |> normalize_thread_state()
    |> normalize_channel_state()
    |> normalize_locks()
    |> normalize_pending_locks()
    |> normalize_concurrency_events()
  end

  def normalize_snapshot(_snapshot), do: default_snapshot()

  defp normalize_subscriptions(snapshot) do
    subscriptions =
      case snapshot.subscriptions do
        %MapSet{} = subscriptions ->
          subscriptions

        subscriptions when is_list(subscriptions) ->
          subscriptions
          |> Enum.map(&to_string/1)
          |> MapSet.new()

        _ ->
          MapSet.new()
      end

    %{snapshot | subscriptions: subscriptions}
  end

  defp normalize_dedupe(snapshot) do
    dedupe =
      case snapshot.dedupe do
        %MapSet{} = dedupe ->
          dedupe

        dedupe when is_list(dedupe) ->
          Enum.reduce(dedupe, MapSet.new(), fn
            [adapter_name, message_id], acc ->
              case normalize_key_atom(adapter_name) do
                {:ok, adapter_atom} -> MapSet.put(acc, {adapter_atom, to_string(message_id)})
                :error -> acc
              end

            {adapter_name, message_id}, acc ->
              case normalize_key_atom(adapter_name) do
                {:ok, adapter_atom} -> MapSet.put(acc, {adapter_atom, to_string(message_id)})
                :error -> acc
              end

            _other, acc ->
              acc
          end)

        _ ->
          MapSet.new()
      end

    %{snapshot | dedupe: dedupe}
  end

  defp normalize_dedupe_order(snapshot) do
    dedupe_order =
      case snapshot.dedupe_order do
        dedupe_order when is_list(dedupe_order) ->
          Enum.reduce(dedupe_order, [], fn
            [adapter_name, message_id], acc ->
              case normalize_key_atom(adapter_name) do
                {:ok, adapter_atom} -> [{adapter_atom, to_string(message_id)} | acc]
                :error -> acc
              end

            {adapter_name, message_id}, acc ->
              case normalize_key_atom(adapter_name) do
                {:ok, adapter_atom} -> [{adapter_atom, to_string(message_id)} | acc]
                :error -> acc
              end

            _other, acc ->
              acc
          end)
          |> Enum.reverse()

        _ ->
          []
      end

    %{snapshot | dedupe_order: dedupe_order}
  end

  defp normalize_thread_state(snapshot) do
    thread_state =
      case snapshot.thread_state do
        thread_state when is_map(thread_state) -> thread_state
        _ -> %{}
      end

    %{snapshot | thread_state: thread_state}
  end

  defp normalize_channel_state(snapshot) do
    channel_state =
      case snapshot.channel_state do
        channel_state when is_map(channel_state) -> channel_state
        _ -> %{}
      end

    %{snapshot | channel_state: channel_state}
  end

  defp normalize_locks(snapshot) do
    locks =
      case snapshot.locks do
        locks when is_map(locks) ->
          locks
          |> Enum.map(fn {key, lock} -> {to_string(key), normalize_lock(lock)} end)
          |> Map.new()

        _ ->
          %{}
      end

    %{snapshot | locks: locks}
  end

  defp normalize_pending_locks(snapshot) do
    pending_locks =
      case snapshot.pending_locks do
        pending when is_map(pending) ->
          pending
          |> Enum.map(fn {key, entries} ->
            normalized_entries =
              if is_list(entries) do
                entries
                |> Enum.filter(&is_map/1)
                |> Enum.map(&normalize_pending_entry/1)
              else
                []
              end

            {to_string(key), normalized_entries}
          end)
          |> Map.new()

        _ ->
          %{}
      end

    %{snapshot | pending_locks: pending_locks}
  end

  defp normalize_concurrency_events(snapshot) do
    events =
      case snapshot.concurrency_events do
        events when is_list(events) ->
          events
          |> Enum.filter(&is_map/1)
          |> Enum.map(&normalize_concurrency_event/1)
          |> Enum.take(-100)

        _ ->
          []
      end

    %{snapshot | concurrency_events: events}
  end

  defp normalize_concurrency_event(event) do
    event
    |> copy_known_fields([
      :event,
      :key,
      :lock_key,
      :owner,
      :message_id,
      :strategy,
      :at,
      :queue_depth,
      :conversation_key,
      :reason,
      :overflow_policy,
      :expired_at,
      :superseded_by,
      :skipped_count,
      :total_count,
      :drained_count
    ])
    |> normalize_event_enum(:event)
    |> normalize_event_enum(:reason)
    |> normalize_event_enum(:overflow_policy)
  end

  defp normalize_event_enum(event, key) do
    case Map.get(event, key) do
      value when is_binary(value) ->
        try do
          Map.put(event, key, String.to_existing_atom(value))
        rescue
          ArgumentError -> event
        end

      _ ->
        event
    end
  end

  defp normalize_lock(lock) when is_map(lock) do
    copy_known_fields(lock, [
      :owner,
      :owners,
      :strategy,
      :metadata,
      :ready_at,
      :conversation_key,
      :max_concurrent
    ])
  end

  defp normalize_lock(_lock), do: %{}

  defp normalize_pending_entry(entry) do
    copy_known_fields(entry, [
      :owner,
      :strategy,
      :metadata,
      :enqueued_at,
      :expires_at,
      :ready_at,
      :conversation_key
    ])
  end

  defp filter_released_entries({{:released, entries}, state}, now_ms) do
    active =
      Enum.filter(entries, fn entry ->
        expires_at = entry[:expires_at] || entry["expires_at"]
        is_nil(expires_at) or expires_at >= now_ms
      end)

    {{:released, active}, state}
  end

  defp filter_released_entries(result, _now_ms), do: result

  defp copy_known_fields(map, fields) do
    Enum.reduce(fields, map, fn field, acc ->
      string_field = Atom.to_string(field)

      if Map.has_key?(acc, string_field) and not Map.has_key?(acc, field) do
        acc |> Map.put(field, Map.get(acc, string_field)) |> Map.delete(string_field)
      else
        acc
      end
    end)
    |> normalize_strategy()
  end

  defp normalize_strategy(%{strategy: strategy} = map) when is_binary(strategy) do
    try do
      %{map | strategy: String.to_existing_atom(strategy)}
    rescue
      ArgumentError -> map
    end
  end

  defp normalize_strategy(map), do: map

  defp fallback_drain(adapter_module, state, key, owner, now_ms, conversation_key) do
    snapshot = snapshot(adapter_module, state)
    lock = Map.get(snapshot.locks, key, %{})
    ready_at = lock[:ready_at] || lock["ready_at"] || 0

    cond do
      (lock[:owner] || lock["owner"]) != owner ->
        {{:error, :not_owner}, state}

      ready_at > now_ms ->
        {{:waiting, %{remaining_ms: ready_at - now_ms}}, state}

      true ->
        {{:released, entries}, next_state} = adapter_module.release_lock(state, key, owner)
        dispatch = fallback_dispatch(entries, now_ms, conversation_key)
        {{:drained, dispatch}, next_state}
    end
  end

  defp fallback_dispatch(entries, now_ms, conversation_key) do
    active =
      Enum.filter(entries, fn entry ->
        expires_at = entry[:expires_at] || entry["expires_at"]
        is_nil(expires_at) or expires_at >= now_ms
      end)

    case List.last(active) do
      nil ->
        nil

      latest ->
        latest_conversation =
          latest[:conversation_key] || latest["conversation_key"] || conversation_key

        skipped =
          active
          |> Enum.drop(-1)
          |> Enum.filter(fn entry ->
            (entry[:conversation_key] || entry["conversation_key"] || conversation_key) ==
              latest_conversation
          end)

        Map.put(latest, :context, Jido.Chat.Concurrency.message_context(skipped))
    end
  end

  defp normalize_key_atom(key) when is_atom(key), do: {:ok, key}

  defp normalize_key_atom(key) when is_binary(key) do
    try do
      {:ok, String.to_existing_atom(key)}
    rescue
      ArgumentError -> :error
    end
  end

  defp normalize_key_atom(_key), do: :error
end
