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
        extensions: [Jido.Chat.Runtime.Room.Plugin]

      routes do
        route("jido.chat.room.join", Jido.Chat.Runtime.Actions.RoomCommand)
        route("jido.chat.room.leave", Jido.Chat.Runtime.Actions.RoomCommand)
        route("jido.chat.room.post", Jido.Chat.Runtime.Actions.RoomCommand)
        route("jido.chat.room.check_member", Jido.Chat.Runtime.Actions.RoomCommand)
      end
    end
  end

  @doc "Returns the schema for a host principal ID or full Agent Ref."
  @spec member_schema() :: Zoi.schema()
  def member_schema, do: Zoi.union([Jido.Agent.Ref.schema(), Zoi.string() |> Zoi.min(1)])

  @doc "Returns a Bus name that includes the complete room identity."
  @spec bus_name(Jido.Agent.Ref.t()) :: String.t()
  def bus_name(%Jido.Agent.Ref{} = ref) do
    key = :erlang.term_to_binary({ref.namespace, ref.partition, ref.id})
    "jido.chat.room/" <> Base.url_encode64(key, padding: false)
  end

  @doc false
  @spec actor(term()) :: Jido.Chat.Actor.t()
  def actor(%Jido.Agent.Ref{} = ref) do
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
