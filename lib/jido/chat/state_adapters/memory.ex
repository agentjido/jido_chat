defmodule Jido.Chat.StateAdapters.Memory do
  @moduledoc """
  Default in-memory state adapter.

  This preserves the current pure-struct semantics while routing all state access
  through the `Jido.Chat.StateAdapter` contract.
  """

  @behaviour Jido.Chat.StateAdapter

  alias Jido.Chat.StateAdapter

  @enforce_keys [:subscriptions, :dedupe, :dedupe_order, :thread_state, :channel_state]
  defstruct subscriptions: MapSet.new(),
            dedupe: MapSet.new(),
            dedupe_order: [],
            thread_state: %{},
            channel_state: %{}

  @type t :: %__MODULE__{
          subscriptions: MapSet.t(String.t()),
          dedupe: MapSet.t(StateAdapter.dedupe_key()),
          dedupe_order: [StateAdapter.dedupe_key()],
          thread_state: %{optional(String.t()) => map()},
          channel_state: %{optional(String.t()) => map()}
        }

  @impl true
  def init(snapshot, _opts \\ []) do
    snapshot = StateAdapter.normalize_snapshot(snapshot)

    %__MODULE__{
      subscriptions: snapshot.subscriptions,
      dedupe: snapshot.dedupe,
      dedupe_order: snapshot.dedupe_order,
      thread_state: snapshot.thread_state,
      channel_state: snapshot.channel_state
    }
  end

  @impl true
  def snapshot(%__MODULE__{} = state) do
    %{
      subscriptions: state.subscriptions,
      dedupe: state.dedupe,
      dedupe_order: state.dedupe_order,
      thread_state: state.thread_state,
      channel_state: state.channel_state
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

  defp trim_dedupe_order(dedupe_order, dedupe_limit) do
    overflow_count = max(length(dedupe_order) - dedupe_limit, 0)

    if overflow_count == 0 do
      {dedupe_order, []}
    else
      {overflow_keys, remaining_keys} = Enum.split(dedupe_order, overflow_count)
      {remaining_keys, overflow_keys}
    end
  end
end
