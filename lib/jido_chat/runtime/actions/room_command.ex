defmodule Jido.Chat.Runtime.Actions.RoomCommand do
  @moduledoc "Builds portable room messages after Room Plugin admission."

  use Jido.Action, name: "chat_room_command", schema: Zoi.map()

  alias Jido.Chat.{Actor, Message, Post}
  alias Jido.Chat.Runtime.Directives.Publish
  alias Jido.Chat.Runtime.Room
  alias Jido.Chat.Runtime.Signal.Room.Message, as: MessageSignal

  @impl true
  def run(_params, context) do
    cond do
      context.signal.type == "jido.chat.room.check_member" ->
        input = context.plugin_inputs[Room.Plugin].prepared
        state = context.agent_state

        retained =
          if Map.has_key?(input, "message_id") and Map.has_key?(input, "message_data") do
            Enum.any?(state.room.messages, &(&1.id == input["message_id"] and &1.data == input["message_data"]))
          else
            not Map.has_key?(input, "message_id") and not Map.has_key?(input, "message_data")
          end

        reply =
          Jido.Chat.Runtime.Signal.Room.MemberChecked.new!(%{
            "member" => input["member"] in state.room.members,
            "retained" => retained
          })
          |> Jido.Signal.put_context("jidocausationid", context.signal.id)

        {:ok, reply} = reply
        {:ok, state, [Jido.Agent.Directive.reply(reply)]}

      context.signal.type == "jido.chat.room.post" ->
        input = context.plugin_inputs[Room.Plugin]
        post = Post.from_map(input.prepared["post"])
        mentions = input.prepared["mentions"]
        state = context.agent_state
        actor = message_actor(post, input.runtime.actor)

        case Enum.find(state.room.messages, &(&1.id == context.signal.id)) do
          nil ->
            message =
              Message.new(%{
                id: context.signal.id,
                room_id: input.runtime.room.id,
                thread_id: post.thread_id,
                reply_to_id: post.reply_to_id,
                actor: actor,
                role: message_role(actor),
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

            {:ok, state, [%Publish{message: fact}, post_reply(context.signal, fact)]}

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
                    actor: actor,
                    role: message_role(actor),
                    content: post.content,
                    metadata: post.metadata
                  })
                ),
              "mentions" => mentions
            }

            if Map.take(previous.data, Map.keys(expected)) == expected,
              do: {:ok, state, [post_reply(context.signal, previous)]},
              else: {:error, :message_id_conflict}
        end

      true ->
        {:ok, context.agent_state, []}
    end
  end

  defp post_reply(request, message) do
    reply = Jido.Chat.Runtime.Signal.Room.Posted.new!(%{"message" => message})
    {:ok, reply} = Jido.Signal.put_context(reply, "jidocausationid", request.id)
    Jido.Agent.Directive.reply(reply)
  end

  defp message_actor(post, local_actor) do
    case get_in(post.metadata, ["jido_chat_origin", "actor"]) do
      actor when is_map(actor) -> Actor.from_map(actor)
      _ -> Room.actor(local_actor)
    end
  end

  defp message_role(%Actor{kind: kind}) when kind in [:agent, :bot], do: :assistant
  defp message_role(%Actor{kind: :system}), do: :system
  defp message_role(%Actor{}), do: :user
end
