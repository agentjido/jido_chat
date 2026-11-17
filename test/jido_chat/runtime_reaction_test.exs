defmodule Jido.Chat.RuntimeReactionTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Runtime.Room.Reaction

  test "builds a portable stable reaction identity" do
    inserted_at = ~U[2026-11-16 10:00:00Z]

    reaction =
      Reaction.new!(%{
        room_id: "team",
        message_id: "message-1",
        reaction: "thumbsup",
        actor: "alice",
        inserted_at: inserted_at,
        updated_at: inserted_at
      })

    same_identity =
      Reaction.new!(%{
        room_id: "team",
        message_id: "message-1",
        reaction: "thumbsup",
        actor: "alice"
      })

    assert reaction.id == same_identity.id
    assert reaction.status == :active
    assert reaction.revision == 1
    assert Reaction.actor(reaction) == "alice"
    assert {:ok, ^reaction} = reaction |> Reaction.to_map() |> Reaction.from_map()

    assert {:error, :invalid_reaction} =
             reaction
             |> Reaction.to_map()
             |> Map.put("id", "changed")
             |> Reaction.from_map()

    assert {:error, :invalid_reaction} =
             reaction
             |> Reaction.to_map()
             |> Map.put("actor_key", "changed")
             |> Reaction.from_map()
  end

  test "normalizes Agent Addresses without losing their identity" do
    address = Jido.Agent.Address.new!(%{namespace: "test", partition: "workers", id: "alice"})
    reaction = Reaction.new!(%{room_id: "team", message_id: "message-1", reaction: "eyes", actor: address})

    assert Reaction.actor(reaction) == address

    assert {:ok, {"team", "message-1", "eyes", actor_key}} =
             Reaction.key("team", "message-1", "eyes", address)

    assert actor_key == reaction.actor_key
  end

  test "transitions only the current state revision" do
    current = Reaction.new!(%{room_id: "team", message_id: "message-1", reaction: "eyes", actor: "alice"})

    assert {:ok, ^current} = Reaction.transition(current, :active)
    assert {:ok, removed} = Reaction.transition(current, :removed)
    assert removed.status == :removed
    assert removed.revision == 2
    assert removed.id == current.id
    assert removed.inserted_at == current.inserted_at
    assert {:error, :invalid_reaction} = Reaction.transition(current, :unknown)
  end

  test "rejects invalid identity and state fields" do
    valid = %{room_id: "team", message_id: "message-1", reaction: "eyes", actor: "alice"}

    assert {:error, :invalid_reaction} = Reaction.new(Map.put(valid, :room_id, ""))
    assert {:error, :invalid_reaction} = Reaction.new(Map.put(valid, :message_id, ""))
    assert {:error, :invalid_reaction} = Reaction.new(Map.put(valid, :reaction, ""))
    assert {:error, :invalid_reaction_actor} = Reaction.new(Map.put(valid, :actor, nil))
    assert {:error, :invalid_reaction} = Reaction.new(Map.put(valid, :status, :unknown))
    assert {:error, :invalid_reaction} = Reaction.new(Map.put(valid, :revision, 0))
    assert {:error, :invalid_reaction} = Reaction.new(Map.put(valid, :extra, true))
  end

  test "reaction command schemas enforce the durable byte limits" do
    alias Jido.Chat.Runtime.Signal.Room.{AddReaction, RemoveReaction}

    assert {:error, _errors} =
             AddReaction.new(%{
               "message_id" => String.duplicate("m", 257),
               "reaction" => "eyes"
             })

    assert {:error, _errors} =
             RemoveReaction.new(%{
               "message_id" => "message-1",
               "reaction" => String.duplicate("👍", 65)
             })
  end
end
