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
          channel_state: %{optional(String.t()) => map()}
        }

  @type state :: term()

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

  @doc "Returns the canonical empty snapshot."
  @spec default_snapshot() :: snapshot()
  def default_snapshot do
    %{
      subscriptions: MapSet.new(),
      dedupe: MapSet.new(),
      dedupe_order: [],
      thread_state: %{},
      channel_state: %{}
    }
  end

  @doc "Normalizes maps, lists, and map-sets into the canonical state snapshot shape."
  @spec normalize_snapshot(map()) :: snapshot()
  def normalize_snapshot(snapshot) when is_map(snapshot) do
    defaults = default_snapshot()

    %{
      subscriptions:
        snapshot[:subscriptions] || snapshot["subscriptions"] || defaults.subscriptions,
      dedupe: snapshot[:dedupe] || snapshot["dedupe"] || defaults.dedupe,
      dedupe_order: snapshot[:dedupe_order] || snapshot["dedupe_order"] || defaults.dedupe_order,
      thread_state: snapshot[:thread_state] || snapshot["thread_state"] || defaults.thread_state,
      channel_state:
        snapshot[:channel_state] || snapshot["channel_state"] || defaults.channel_state
    }
    |> normalize_subscriptions()
    |> normalize_dedupe()
    |> normalize_dedupe_order()
    |> normalize_thread_state()
    |> normalize_channel_state()
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
              MapSet.put(acc, {normalize_key_atom(adapter_name), to_string(message_id)})

            {adapter_name, message_id}, acc ->
              MapSet.put(acc, {normalize_key_atom(adapter_name), to_string(message_id)})

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
              [{normalize_key_atom(adapter_name), to_string(message_id)} | acc]

            {adapter_name, message_id}, acc ->
              [{normalize_key_atom(adapter_name), to_string(message_id)} | acc]

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

  defp normalize_key_atom(key) when is_atom(key), do: key
  defp normalize_key_atom(key) when is_binary(key), do: String.to_atom(key)
  defp normalize_key_atom(key), do: key
end
