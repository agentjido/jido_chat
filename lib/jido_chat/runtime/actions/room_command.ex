defmodule Jido.Chat.Runtime.Actions.RoomCommand do
  @moduledoc "Builds portable room messages after Room Plugin admission."

  use Jido.Action, name: "chat_room_command", schema: Zoi.map()

  alias Jido.Chat.{Actor, Message, Post}
  alias Jido.Chat.Runtime.Directives.Publish
  alias Jido.Chat.Runtime.Room
  alias Jido.Chat.Runtime.Room.{Durable, Membership}
  alias Jido.Chat.Runtime.Signal.Room.Message, as: MessageSignal

  @impl true
  def run(_params, context) do
    cond do
      context.signal.type == "jido.chat.room.join" ->
        input = context.plugin_inputs[Room.Plugin]

        with :ok <-
               persist_membership(
                 input.runtime.durable_runtime,
                 :join,
                 input.runtime.room.id,
                 input.prepared["member"],
                 input.runtime.actor
               ) do
          {:ok, context.agent_state, []}
        end

      context.signal.type == "jido.chat.room.leave" ->
        input = context.plugin_inputs[Room.Plugin]

        with :ok <-
               persist_membership(
                 input.runtime.durable_runtime,
                 :leave,
                 input.runtime.room.id,
                 input.prepared["member"],
                 input.runtime.actor
               ) do
          {:ok, context.agent_state, []}
        end

      context.signal.type == "jido.chat.room.check_member" ->
        plugin_input = context.plugin_inputs[Room.Plugin]
        input = plugin_input.prepared
        state = context.agent_state

        {member, retained} =
          membership_evidence(
            plugin_input.runtime.durable_runtime,
            plugin_input.runtime.room.id,
            input,
            state
          )

        reply =
          Jido.Chat.Runtime.Signal.Room.MemberChecked.new!(%{
            "member" => member,
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

        case committed_fact(input.runtime.durable_runtime, input.runtime.room.id, state.room.messages, fact) do
          {:ok, committed, retain} ->
            {:ok, state,
             [
               %Publish{message: committed, retain: retain},
               post_reply(context.signal, committed)
             ]}

          {:error, _reason} = error ->
            error
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

  defp persist_membership(nil, _action, _room_id, _member, _issuer), do: :ok

  defp persist_membership(runtime, :join, room_id, member, issuer) do
    with {:ok, _membership} <- Durable.join(runtime, room_id, member, issuer), do: :ok
  end

  defp persist_membership(runtime, :leave, room_id, member, issuer) do
    with {:ok, _membership} <- Durable.leave(runtime, room_id, member, issuer), do: :ok
  end

  defp committed_fact(nil, _room_id, messages, fact) do
    case Enum.find(messages, &(&1.id == fact.id)) do
      nil -> {:ok, fact, true}
      previous -> if same_fact?(previous, fact), do: {:ok, previous, false}, else: {:error, :message_id_conflict}
    end
  end

  defp committed_fact(runtime, room_id, _messages, fact) do
    with {:ok, existing} <- Durable.get_message(runtime, room_id, fact.id),
         {:ok, record} <- Durable.store_message(runtime, room_id, fact) do
      {:ok, record.signal, is_nil(existing)}
    end
  end

  defp same_fact?(left, right) do
    left.id == right.id and left.type == right.type and
      Map.delete(left.data, "sequence") == Map.delete(right.data, "sequence")
  end

  defp membership_evidence(nil, _room_id, input, state) do
    {input["member"] in state.room.members, retained?(state.room.messages, input)}
  end

  defp membership_evidence(runtime, room_id, input, _state) do
    member =
      case Durable.get_membership(runtime, room_id, input["member"]) do
        {:ok, %Membership{status: :active}} -> true
        _ -> false
      end

    retained =
      if Map.has_key?(input, "message_id") and Map.has_key?(input, "message_data") do
        case Durable.get_message(runtime, room_id, input["message_id"]) do
          {:ok, %{signal: signal}} -> signal.data == input["message_data"]
          _ -> false
        end
      else
        not Map.has_key?(input, "message_id") and not Map.has_key?(input, "message_data")
      end

    {member, retained}
  end

  defp retained?(messages, input) do
    if Map.has_key?(input, "message_id") and Map.has_key?(input, "message_data") do
      Enum.any?(messages, &(&1.id == input["message_id"] and &1.data == input["message_data"]))
    else
      not Map.has_key?(input, "message_id") and not Map.has_key?(input, "message_data")
    end
  end
end
