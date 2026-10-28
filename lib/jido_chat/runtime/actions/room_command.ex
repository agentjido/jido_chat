defmodule Jido.Chat.Runtime.Actions.RoomCommand do
  @moduledoc "Builds portable room messages after Room Plugin admission."

  use Jido.Action, name: "chat_room_command", schema: Zoi.map()

  alias Jido.Chat.{Actor, Message, Post}
  alias Jido.Chat.Runtime.Directives.Publish
  alias Jido.Chat.Runtime.Room
  alias Jido.Chat.Runtime.Signal.Room.Message, as: MessageSignal

  @impl true
  def run(_params, context) do
    if context.signal.type == "jido.chat.room.post" do
      input = context.plugin_inputs[Room.Plugin]
      post = Post.from_map(input.prepared["post"])
      mentions = input.prepared["mentions"]
      state = context.agent_state

      case Enum.find(state.room.messages, &(&1.id == context.signal.id)) do
        nil ->
          message =
            Message.new(%{
              id: context.signal.id,
              room_id: input.runtime.room.id,
              thread_id: post.thread_id,
              reply_to_id: post.reply_to_id,
              actor: message_actor(post, input.runtime.actor),
              content: post.content,
              metadata: post.metadata
            })

          fact =
            MessageSignal.new!(
              %{
                "room" => input.runtime.room,
                "sequence" => state.room.sequence + 1,
                "author" => input.runtime.actor,
                "message" => Message.to_map(message),
                "mentions" => mentions
              },
              id: context.signal.id
            )

          {:ok, state, [%Publish{message: fact}]}

        previous ->
          expected = %{
            "room" => input.runtime.room,
            "author" => input.runtime.actor,
            "message" =>
              Message.to_map(
                Message.new(%{
                  id: context.signal.id,
                  room_id: input.runtime.room.id,
                  thread_id: post.thread_id,
                  reply_to_id: post.reply_to_id,
                  actor: message_actor(post, input.runtime.actor),
                  content: post.content,
                  metadata: post.metadata
                })
              ),
            "mentions" => mentions
          }

          if Map.take(previous.data, Map.keys(expected)) == expected,
            do: {:ok, state, []},
            else: {:error, :message_id_conflict}
      end
    else
      {:ok, context.agent_state, []}
    end
  end

  defp message_actor(post, local_actor) do
    case get_in(post.metadata, ["jido_chat_origin", "actor"]) do
      actor when is_map(actor) -> Actor.from_map(actor)
      _ -> Room.actor(local_actor)
    end
  end
end
