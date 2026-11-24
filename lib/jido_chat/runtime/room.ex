defmodule Jido.Chat.Runtime.Room do
  @moduledoc """
  Defines a local room Agent with bounded membership and working history.

  The host starts the room through its Jido instance. Starting `:jido_chat`
  starts no room or Bus process.
  """

  @stop_timeout 5_000
  @stop_poll_interval 5

  defmacro __using__(opts) do
    quote do
      use Jido.Agent,
        name: unquote(Keyword.fetch!(opts, :name)),
        plugins: [Jido.Chat.Runtime.Room.Plugin]

      routes do
        route("jido.chat.room.join", Jido.Chat.Runtime.Actions.RoomCommand)
        route("jido.chat.room.leave", Jido.Chat.Runtime.Actions.RoomCommand)
        route("jido.chat.room.post", Jido.Chat.Runtime.Actions.RoomCommand)
        route("jido.chat.room.reaction.add", Jido.Chat.Runtime.Actions.RoomCommand)
        route("jido.chat.room.reaction.remove", Jido.Chat.Runtime.Actions.RoomCommand)
        route("jido.chat.room.check_member", Jido.Chat.Runtime.Actions.RoomCommand)
      end
    end
  end

  @doc "Starts a room or participant at its complete Address through the host instance."
  @spec start_agent(atom(), Jido.Agent.Address.t(), module() | Jido.Agent.t()) ::
          {:ok, pid()} | {:error, term()}
  def start_agent(jido, %Jido.Agent.Address{} = address, agent), do: start_agent(jido, address, agent, [])

  @doc false
  @spec start_agent(atom(), Jido.Agent.Address.t(), module() | Jido.Agent.t(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def start_agent(jido, %Jido.Agent.Address{} = address, agent, opts) do
    with {:ok, ^address} <- Jido.agent_address(jido, address.id, partition: address.partition) do
      Jido.start_agent(jido, agent, Keyword.merge(opts, id: address.id, partition: address.partition))
    else
      _ -> {:error, :address_mismatch}
    end
  end

  @doc "Stops the resident worker at one Address without deleting stored data."
  @spec stop_agent(atom(), Jido.Agent.Address.t()) :: :ok | {:error, term()}
  def stop_agent(jido, address) do
    with {:ok, server} <- Jido.resolve_agent(jido, address) do
      stop_resolved_agent(jido, address, server)
    end
  end

  @doc false
  def stop_matching_agent(jido, ref, server, expected) do
    case Jido.AgentServer.snapshot(server) do
      %Jido.AgentServer.Snapshot{agent: actual, agent_address: ^ref} ->
        if same_definition?(expected, actual) do
          stop_resolved_agent(jido, ref, server)
        else
          {:error, :address_in_use}
        end

      %Jido.AgentServer.Snapshot{} ->
        {:error, :address_mismatch}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Checks membership and optional retained message in one correlated room turn."
  @spec check_member(atom(), Jido.Agent.Address.t(), term(), Jido.Signal.t() | nil) ::
          :ok | {:error, term()}
  def check_member(jido, room, member, message \\ nil) do
    data =
      if message,
        do: %{"member" => member, "message_id" => message.id, "message_data" => message.data},
        else: %{"member" => member}

    request = Jido.Chat.Runtime.Signal.Room.CheckMember.new!(data)

    with {:ok, %Jido.AgentServer.TurnResult{status: :committed, reply: %Jido.Signal{} = reply}} <-
           Jido.call(jido, room, request, context: %{actor: member}),
         true <- reply.type == Jido.Chat.Runtime.Signal.Room.MemberChecked.type(),
         true <- Jido.Signal.get_context(reply, "jidocausationid") == request.id,
         {:ok, %{"member" => true, "retained" => true}} <-
           Jido.Chat.Runtime.Signal.Room.MemberChecked.validate_data(reply.data) do
      :ok
    else
      _ -> {:error, :not_member_or_retained_message}
    end
  end

  @doc "Returns the schema for a host principal ID or full Agent Address."
  @spec member_schema() :: Jido.Joi.schema()
  defdelegate member_schema(), to: Jido.Chat.Runtime.Signal.Room

  @doc "Returns a Bus name that includes the complete room identity."
  @spec bus_name(Jido.Agent.Address.t()) :: String.t()
  def bus_name(%Jido.Agent.Address{} = ref) do
    key = :erlang.term_to_binary({ref.namespace, ref.partition, ref.id})
    "jido.chat.room/" <> Base.url_encode64(key, padding: false)
  end

  @doc false
  @spec actor(term()) :: Jido.Chat.Actor.t()
  def actor(%Jido.Agent.Address{} = ref) do
    Jido.Chat.Actor.new(%{
      id: ref.id,
      kind: :agent,
      metadata: %{
        "namespace" => ref.namespace,
        "partition" => ref.partition
      }
    })
  end

  def actor(id) when is_binary(id), do: Jido.Chat.Actor.new(%{id: id, kind: :human})

  @doc false
  def same_definition?(%{module: module, vsn: vsn}, %{module: module, vsn: vsn})
      when module not in [nil, true, false],
      do: true

  def same_definition?(expected, actual),
    do: definition_key(expected) == definition_key(actual)

  defp stop_resolved_agent(jido, address, server) do
    case Jido.stop_agent(jido, server, partition: address.partition) do
      :ok -> await_stopped(jido, address, System.monotonic_time(:millisecond) + @stop_timeout)
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp await_stopped(jido, address, deadline) do
    case Jido.resolve_agent(jido, address) do
      {:error, :not_found} ->
        :ok

      result when result in [{:error, :recovering}, {:error, :passivating}] ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(@stop_poll_interval)
          await_stopped(jido, address, deadline)
        else
          {:error, :agent_stop_timeout}
        end

      {:ok, _server} ->
        {:error, :agent_still_running}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp definition_key(agent) do
    {
      agent.module,
      agent.name,
      agent.vsn,
      agent.signal_source,
      Enum.map(agent.plugins, & &1.provider),
      Enum.map(agent.routes, &Map.take(&1, [:type, :target]))
    }
  end
end
