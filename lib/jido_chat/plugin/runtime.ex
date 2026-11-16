defmodule Jido.Chat.Plugin.Runtime do
  @moduledoc "Holds resolved Clients for one Agent activation."
  use GenServer

  @identity_ttl_seconds 30
  @identity_limit 1_024

  @doc "Starts the resolved Client store for one Agent activation."
  @spec start_link({pid(), [map()]}) :: GenServer.on_start()
  def start_link({server, connections}),
    do: start_link({server, connections, disabled_access()})

  @doc false
  @spec start_link({pid(), [map()], map()}) :: GenServer.on_start()
  def start_link({server, connections, access}),
    do: GenServer.start_link(__MODULE__, {connections, access}, name: {:global, {__MODULE__, server}})

  @doc "Returns the activated connections for an AgentServer."
  @spec connections(pid()) :: [map()]
  def connections(server), do: GenServer.call({:global, {__MODULE__, server}}, :connections)

  @doc false
  @spec access(pid()) :: map()
  def access(server), do: GenServer.call({:global, {__MODULE__, server}}, :access)

  @doc false
  @spec access_from_runtime(pid()) :: map()
  def access_from_runtime(runtime), do: GenServer.call(store(runtime), :access)

  @doc false
  @spec register_identity(pid(), String.t(), Jido.Signal.t(), Jido.Chat.Principal.t()) ::
          :ok | {:error, atom()}
  def register_identity(server, client_id, signal, principal) do
    GenServer.call({:global, {__MODULE__, server}}, {:register_identity, client_id, signal, principal})
  end

  @doc false
  @spec consume_identity(pid(), String.t(), Jido.Signal.t()) ::
          {:ok, Jido.Chat.Principal.t()} | {:error, atom()}
  def consume_identity(runtime, client_id, signal) do
    GenServer.call(store(runtime), {:consume_identity, client_id, signal})
  end

  @doc false
  @spec inbound_client(pid(), String.t()) :: String.t() | nil
  def inbound_client(runtime, source), do: GenServer.call(store(runtime), {:inbound_client, source})

  @impl true
  def init({connections, access}) do
    {:ok, %{connections: connections, access: access, identities: %{}, interactions: %{}, sensors: %{}}}
  end

  @impl true
  def handle_call(:connections, _from, state), do: {:reply, state.connections, state}
  def handle_call(:access, _from, state), do: {:reply, state.access, state}

  def handle_call({:inbound_client, source}, _from, state) do
    client_id =
      case Enum.find(state.connections, &(&1.client.source == source)) do
        nil -> nil
        connection -> connection.client.id
      end

    {:reply, client_id, state}
  end

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
    {:reply, :ok, remember_interaction(state, client_id, signal)}
  end

  def handle_call({:register_identity, client_id, signal, principal}, _from, state) do
    state = prune_identities(state)

    if map_size(state.identities) >= @identity_limit do
      {:reply, {:error, :identity_admission_overloaded}, state}
    else
      key = {client_id, signal.id}
      expires = System.monotonic_time(:second) + @identity_ttl_seconds
      identities = Map.put(state.identities, key, {signal, principal, expires})
      {:reply, :ok, remember_interaction(%{state | identities: identities}, client_id, signal)}
    end
  end

  def handle_call({:consume_identity, client_id, signal}, _from, state) do
    state = prune_identities(state)
    key = {client_id, signal.id}
    {entry, identities} = Map.pop(state.identities, key)

    case entry do
      {^signal, principal, _expires} ->
        {:reply, {:ok, principal}, %{state | identities: identities}}

      nil ->
        {:reply, {:error, :identity_admission_missing}, state}

      _other ->
        {:reply, {:error, :identity_admission_mismatch}, %{state | identities: identities}}
    end
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

  defp remember_interaction(state, client_id, signal) do
    now = System.monotonic_time(:second)
    interactions = Map.reject(state.interactions, fn {_, {_, expires}} -> expires <= now end)

    interactions =
      case signal.data["interaction_id"] do
        nil -> interactions
        id -> Map.put(interactions, {client_id, id}, {signal.data["room_id"], now + 30})
      end

    %{state | interactions: interactions}
  end

  defp prune_identities(state) do
    now = System.monotonic_time(:second)
    identities = Map.reject(state.identities, fn {_key, {_signal, _principal, expires}} -> expires <= now end)
    %{state | identities: identities}
  end

  defp store(runtime) do
    case Enum.find(Supervisor.which_children(runtime), fn {id, _, _, _} ->
           id == {__MODULE__, :connections}
         end) do
      {_, store, _, _} when is_pid(store) -> store
      _other -> raise ArgumentError, "Chat Plugin runtime store is unavailable"
    end
  end

  defp disabled_access do
    %{
      identity_provider: nil,
      identity_options: %{},
      authorizer: nil,
      authorization_options: %{}
    }
  end
end
