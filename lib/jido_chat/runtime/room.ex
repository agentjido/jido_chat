defmodule Jido.Chat.Runtime.Room do
  @moduledoc """
  Defines a local room Agent with bounded membership and working history.

  The host starts the room through its Jido instance. Starting `:jido_chat`
  starts no room or Bus process.
  """

  defmacro __using__(opts) do
    quote do
      use Jido.Agent,
        name: unquote(Keyword.fetch!(opts, :name)),
        plugins: [Jido.Chat.Runtime.Room.Plugin]

      routes do
        route("jido.chat.room.join", Jido.Chat.Runtime.Actions.RoomCommand)
        route("jido.chat.room.leave", Jido.Chat.Runtime.Actions.RoomCommand)
        route("jido.chat.room.post", Jido.Chat.Runtime.Actions.RoomCommand)
        route("jido.chat.room.check_member", Jido.Chat.Runtime.Actions.RoomCommand)
      end
    end
  end

  @doc "Starts a room or participant at its complete Address."
  @spec start_agent(atom(), Jido.Agent.Address.t(), module() | Jido.Agent.t()) ::
          {:ok, pid()} | {:error, term()}
  def start_agent(jido, %Jido.Agent.Address{} = address, agent) do
    with {:ok, ^address} <- Jido.agent_address(jido, address.id, partition: address.partition) do
      Jido.start_agent(jido, agent, id: address.id, partition: address.partition)
    else
      _ -> {:error, :address_mismatch}
    end
  end

  @doc "Stops the resident worker at one Address without deleting stored data."
  @spec stop_agent(atom(), Jido.Agent.Address.t()) :: :ok | {:error, term()}
  def stop_agent(jido, address) do
    with {:ok, server} <- Jido.resolve_agent(jido, address) do
      Jido.stop_agent(jido, server, partition: address.partition)
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
  @spec member_schema() :: Zoi.schema()
  def member_schema, do: Zoi.union([Jido.Agent.Address.schema(), Zoi.string() |> Zoi.min(1)])

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
end
