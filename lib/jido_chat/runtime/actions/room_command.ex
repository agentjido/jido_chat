defmodule Jido.Chat.Runtime.Actions.RoomCommand do
  @moduledoc "Builds portable room messages after Room Plugin admission."

  use Jido.Action, name: "chat_room_command", schema: Jido.Joi.map()

  alias Jido.Chat.{Actor, Message, Post}
  alias Jido.Chat.Runtime.Directives.Publish
  alias Jido.Chat.Runtime.Room
  alias Jido.Chat.Runtime.Room.{Durable, Membership, Reaction}
  alias Jido.Chat.Runtime.Signal.Room.Message, as: MessageSignal
  alias Jido.Chat.Signal.{ReactionAdded, ReactionRemoved}

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

      context.signal.type in ["jido.chat.room.reaction.add", "jido.chat.room.reaction.remove"] ->
        input = context.plugin_inputs[Room.Plugin]
        status = if context.signal.type == "jido.chat.room.reaction.add", do: :active, else: :removed

        with runtime when not is_nil(runtime) <- input.runtime.durable_runtime,
             {:ok, result} <-
               Durable.change_reaction(
                 runtime,
                 input.runtime.room.id,
                 input.prepared["message_id"],
                 input.prepared["reaction"],
                 input.runtime.actor,
                 status
               ) do
          fact = reaction_fact(result, input.runtime.room.id)
          directives = reaction_directives(context.signal, result, fact)
          {:ok, context.agent_state, directives}
        else
          nil -> {:error, :reaction_storage_required}
          {:error, _reason} = error -> error
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

  defp reaction_fact(%{changed: false}, _room_id), do: nil

  defp reaction_fact(%{reaction: reaction, message: message}, room_id) do
    module = if reaction.status == :active, do: ReactionAdded, else: ReactionRemoved
    event = if reaction.status == :active, do: "added", else: "removed"
    id = "#{reaction.id}/#{event}/#{reaction.revision}"
    actor = Reaction.actor(reaction)

    module.new!(
      %{
        "item_id" => reaction.id,
        "delivery_id" => id,
        "room_id" => room_id,
        "message_id" => reaction.message_id,
        "actor_id" => actor_id(actor),
        "reaction" => reaction.reaction,
        "thread_id" => message.thread_id
      },
      id: id,
      source: "urn:jido:chat:runtime:room"
    )
  end

  defp reaction_directives(request, result, fact) do
    reply =
      Jido.Chat.Runtime.Signal.Room.ReactionChanged.new!(%{
        "record_id" => result.reaction.id,
        "message_id" => result.reaction.message_id,
        "reaction" => result.reaction.reaction,
        "actor" => Reaction.actor(result.reaction),
        "status" => Atom.to_string(result.reaction.status),
        "revision" => result.reaction.revision,
        "changed" => result.changed,
        "fact" => fact
      })

    {:ok, reply} = Jido.Signal.put_context(reply, "jidocausationid", request.id)
    reply = Jido.Agent.Directive.reply(reply)

    if fact, do: [%Publish{message: fact, retain: false}, reply], else: [reply]
  end

  defp actor_id(%Jido.Agent.Address{id: id}), do: id
  defp actor_id(id) when is_binary(id), do: id

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
