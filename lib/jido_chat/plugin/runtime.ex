defmodule Jido.Chat.Plugin.Runtime do
  @moduledoc "Holds resolved Clients for one Agent activation."
  use GenServer

  @doc "Starts the resolved Client store for one Agent activation."
  @spec start_link({pid(), [map()]}) :: GenServer.on_start()
  def start_link({server, connections}),
    do: GenServer.start_link(__MODULE__, connections, name: {:global, {__MODULE__, server}})

  @doc "Returns the activated connections for an AgentServer."
  @spec connections(pid()) :: [map()]
  def connections(server), do: GenServer.call({:global, {__MODULE__, server}}, :connections)
  @impl true
  def init(connections), do: {:ok, %{connections: connections, interactions: %{}, sensors: %{}}}
  @impl true
  def handle_call(:connections, _from, state), do: {:reply, state.connections, state}

  def handle_call(:status, _from, state) do
    status =
      Map.new(state.connections, fn connection ->
        value =
          case {connection.source, state.sensors[connection.name]} do
            {nil, _} ->
              %{process: :disabled, provider: :unknown}

            {_, {pid, provider}} ->
              if Process.alive?(pid),
                do: %{process: :running, provider: provider},
                else: %{process: :stopped, provider: :unknown}

            _ ->
              %{process: :starting, provider: :unknown}
          end

        {connection.name, value}
      end)

    {:reply, status, state}
  end

  def handle_call({:admit, client_id, signal}, _from, state) do
    now = System.monotonic_time(:second)
    interactions = Map.reject(state.interactions, fn {_, {_, expires}} -> expires <= now end)

    interactions =
      case signal.data["interaction_id"] do
        nil -> interactions
        id -> Map.put(interactions, {client_id, id}, {signal.data["room_id"], now + 30})
      end

    {:reply, :ok, %{state | interactions: interactions}}
  end

  def handle_call({:interaction_room, client_id, id}, _from, state) do
    room =
      case state.interactions[{client_id, id}] do
        {room, expires} -> if expires > System.monotonic_time(:second), do: room
        _ -> nil
      end

    {:reply, room, state}
  end

  @impl true
  def handle_cast({:sensor_status, name, pid, provider}, state),
    do: {:noreply, %{state | sensors: Map.put(state.sensors, name, {pid, provider})}}
end
