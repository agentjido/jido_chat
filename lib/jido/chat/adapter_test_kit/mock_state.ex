defmodule Jido.Chat.AdapterTestKit.MockState do
  @moduledoc """
  A small deterministic state process for adapter tests.

  Each process keeps its initial snapshot so a test can reset it without global
  application state.
  """

  use GenServer

  @type server :: GenServer.server()

  @doc "Starts a mock state process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    initial = Keyword.get(opts, :initial, %{})
    GenServer.start_link(__MODULE__, initial, Keyword.take(opts, [:name]))
  end

  @doc "Gets one key from the current state."
  @spec get(server(), term(), term()) :: term()
  def get(server, key, default \\ nil), do: GenServer.call(server, {:get, key, default})

  @doc "Puts one key in the current state."
  @spec put(server(), term(), term()) :: :ok
  def put(server, key, value), do: GenServer.call(server, {:put, key, value})

  @doc "Updates the current state and returns the new snapshot."
  @spec update(server(), (map() -> map())) :: map()
  def update(server, fun) when is_function(fun, 1), do: GenServer.call(server, {:update, fun})

  @doc "Returns the current state snapshot."
  @spec snapshot(server()) :: map()
  def snapshot(server), do: GenServer.call(server, :snapshot)

  @doc "Restores the initial state snapshot."
  @spec reset(server()) :: :ok
  def reset(server), do: GenServer.call(server, :reset)

  @impl true
  def init(initial) when is_map(initial), do: {:ok, %{initial: initial, current: initial}}

  @impl true
  def handle_call({:get, key, default}, _from, state) do
    {:reply, Map.get(state.current, key, default), state}
  end

  def handle_call({:put, key, value}, _from, state) do
    {:reply, :ok, %{state | current: Map.put(state.current, key, value)}}
  end

  def handle_call({:update, fun}, _from, state) do
    current = fun.(state.current)
    {:reply, current, %{state | current: current}}
  end

  def handle_call(:snapshot, _from, state), do: {:reply, state.current, state}
  def handle_call(:reset, _from, state), do: {:reply, :ok, %{state | current: state.initial}}
end
