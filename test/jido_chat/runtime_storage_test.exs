defmodule Jido.Chat.RuntimeStorageTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Runtime.Bridge.Binding
  alias Jido.Chat.Runtime.Connection.Declaration, as: ConnectionDeclaration
  alias Jido.Chat.Runtime.Room.{Declaration, HistoryRecord, Membership, Reaction, Record}
  alias Jido.Chat.Runtime.Storage

  alias Jido.Chat.Runtime.Storage.{
    Adapter,
    Bindings,
    Commit,
    Connections,
    Links,
    Memory,
    Outbox,
    Reactions,
    Rooms
  }

  defmodule LinksOnly do
    use Adapter, capabilities: [Links]

    @impl Links
    def put_link(_resource, link), do: {:ok, link}

    @impl Links
    def link_for_local(_resource, _account_id, _local_id), do: {:ok, nil}

    @impl Links
    def links_for_local(_resource, _account_id, _local_id), do: {:ok, []}

    @impl Links
    def link_for_external(_resource, _account_id, _room_id, _message_id), do: {:ok, nil}
  end

  defmodule CallbackOnly do
    def put_link(_resource, link), do: {:ok, link}
    def link_for_local(_resource, _account_id, _local_id), do: {:ok, nil}
    def links_for_local(_resource, _account_id, _local_id), do: {:ok, []}
    def link_for_external(_resource, _account_id, _room_id, _message_id), do: {:ok, nil}
  end

  defmodule FalseDeclaration do
    def __storage_capabilities__, do: [Links]
  end

  defmodule PartialRuntime do
    def storage, do: {Jido.Chat.RuntimeStorageTest.LinksOnly, :resource}
    def connection_definition("provider"), do: {:ok, __MODULE__}
  end

  setup do
    start_supervised!(Memory)
    |> then(&%{storage: &1})
  end

  test "Memory implements every merge-scope capability", %{storage: storage} do
    assert :ok == Storage.validate({Memory, storage}, [Links, Outbox, Reactions, Rooms, Commit])

    assert Storage.capabilities(Memory) == [
             Links,
             Outbox,
             Reactions,
             Rooms,
             Jido.Chat.Runtime.Storage.RoomDeclarations,
             Jido.Chat.Runtime.Storage.Memberships,
             Jido.Chat.Runtime.Storage.History,
             Connections,
             Bindings,
             Commit
           ]
  end

  test "adapter declarations are additive and checked against callbacks" do
    assert :ok = Storage.validate({LinksOnly, :resource}, [Links])

    assert {:error, :unsupported_storage_capability} =
             Storage.validate({LinksOnly, :resource}, [Outbox])

    assert :ok = Storage.validate({CallbackOnly, :resource}, [Links])

    assert {:error, :unsupported_storage_capability} =
             Storage.validate({FalseDeclaration, :resource}, [Links])
  end

  test "durable connections fail when the adapter lacks the capability" do
    assert {:error, :unsupported_storage_capability} =
             Jido.Chat.Runtime.Connection.Durable.create(
               PartialRuntime,
               "provider",
               %{account_id: "support"}
             )
  end

  test "links are available by local and provider identity", %{storage: storage} do
    link = %{
      account_id: "support",
      local_message_id: "local-1",
      external_room_id: "provider-room",
      external_message_id: "provider-1"
    }

    assert {:ok, ^link} = Memory.put_link(storage, link)
    assert {:ok, ^link} = Memory.link_for_local(storage, "support", "local-1")
    assert {:ok, [^link]} = Memory.links_for_local(storage, "support", "local-1")
    assert {:ok, ^link} = Memory.link_for_external(storage, "support", "provider-room", "provider-1")

    second =
      Map.merge(link, %{
        external_room_id: "provider-room-2",
        external_message_id: "provider-2"
      })

    assert {:ok, ^second} = Memory.put_link(storage, second)
    assert {:ok, ^link} = Memory.link_for_local(storage, "support", "local-1")
    assert {:ok, [^link, ^second]} = Memory.links_for_local(storage, "support", "local-1")
  end

  test "snapshot restore validates and migrates both link indexes" do
    link = %{
      account_id: "support",
      local_message_id: "local-restore",
      external_room_id: "provider-room",
      external_message_id: "provider-restore"
    }

    assert {:ok, ^link, engine} =
             Jido.Chat.Runtime.Storage.Engine.command(
               Jido.Chat.Runtime.Storage.Engine.new(),
               {:put_link, link}
             )

    legacy = %{engine | links_local: %{{"support", "local-restore"} => link}}
    assert {:ok, restored} = Jido.Chat.Runtime.Storage.Engine.restore(legacy)

    assert {:ok, ^link} =
             Jido.Chat.Runtime.Storage.Engine.query(restored, {:link_for_local, "support", "local-restore"})

    assert {:error, :invalid_storage_snapshot} =
             engine
             |> Map.put(:links_external, %{})
             |> Jido.Chat.Runtime.Storage.Engine.restore()

    assert {:error, :invalid_storage_snapshot} =
             engine
             |> Map.put(:links_local, %{{"support", "local-restore"} => %{}})
             |> Jido.Chat.Runtime.Storage.Engine.restore()
  end

  test "outbox enforces explicit delivery transitions", %{storage: storage} do
    work = %{id: "work-1", account_id: "support", status: :pending, payload: %{}}

    assert {:ok, ^work} = Memory.put_work(storage, work)
    assert {:ok, claimed} = Memory.update_work(storage, "work-1", :pending, %{status: :claimed})
    assert claimed.status == :claimed

    assert {:ok, submitted} =
             Memory.update_work(storage, "work-1", :claimed, %{status: :submitted})

    assert submitted.status == :submitted

    assert {:error, :invalid_work_transition} =
             Memory.update_work(storage, "work-1", :submitted, %{status: :pending})

    assert {:ok, completed} =
             Memory.update_work(storage, "work-1", :submitted, %{
               status: :completed,
               result: %{"id" => "provider-1"}
             })

    assert completed.status == :completed
    assert {:ok, [^completed]} = Memory.list_work(storage, "support", status: :completed)
  end

  test "commit applies all commands or none", %{storage: storage} do
    link = %{
      account_id: "support",
      local_message_id: "local-atomic",
      external_room_id: "provider-room",
      external_message_id: "provider-atomic"
    }

    assert {:error, :invalid_work} =
             Memory.commit(storage, [
               {:put_link, link},
               {:put_work, %{id: "bad", account_id: "support", status: :invalid}}
             ])

    assert {:ok, nil} = Memory.link_for_local(storage, "support", "local-atomic")

    work = %{id: "work-atomic", account_id: "support", status: :pending}

    assert {:ok, [^link, ^work]} =
             Memory.commit(storage, [
               {:put_link, link},
               {:put_work, work}
             ])

    assert {:ok, ^link} = Memory.link_for_local(storage, "support", "local-atomic")
    assert {:ok, ^work} = Memory.get_work(storage, "work-atomic")
  end

  test "rooms use stable bounded queries", %{storage: storage} do
    first = room("room/a", :group, ~U[2026-11-16 10:00:00Z])
    second = room("room/b", :direct, ~U[2026-11-16 10:00:00Z])
    third = room("room/c", :group, ~U[2026-11-16 10:00:01Z])

    assert {:ok, ^third} = Memory.insert_room(storage, third)
    assert {:ok, ^second} = Memory.insert_room(storage, second)
    assert {:ok, ^first} = Memory.insert_room(storage, first)
    assert {:ok, ^first} = Memory.insert_room(storage, first)

    assert {:error, :room_conflict} =
             Memory.insert_room(storage, %{first | name: "Different"})

    assert {:ok, ^second} = Memory.get_room(storage, second.id)
    assert {:ok, [^first, ^second, ^third]} = Memory.list_rooms(storage)
    assert {:ok, [^first]} = Memory.list_rooms(storage, kind: :group, limit: 1)
    assert {:ok, [^third]} = Memory.list_rooms(storage, after: second.id, kind: :group)

    assert {:error, :invalid_room_cursor} = Memory.list_rooms(storage, after: "room/missing")
    assert {:error, :invalid_room_kind} = Memory.list_rooms(storage, kind: :invalid)
    assert {:error, :invalid_limit} = Memory.list_rooms(storage, limit: 0)
    assert {:error, :invalid_options} = Memory.list_rooms(storage, [1])
  end

  test "room updates and deletes require the current revision", %{storage: storage} do
    record = room("room/revision", :channel, ~U[2026-11-16 10:00:00Z])
    assert {:ok, ^record} = Memory.insert_room(storage, record)
    assert {:ok, next} = Record.update(record, %{name: "Next"})

    assert {:error, :room_conflict} =
             Memory.update_room(storage, record.id, 2, next)

    assert {:ok, ^next} = Memory.update_room(storage, record.id, 1, next)
    assert {:error, :room_conflict} = Memory.delete_room(storage, record.id, 1)
    assert {:ok, :ok} = Memory.delete_room(storage, record.id, 2)
    assert {:ok, nil} = Memory.get_room(storage, record.id)
  end

  test "a failed Commit leaves no partial Room state", %{storage: storage} do
    record = room("room/atomic", :group, ~U[2026-11-16 10:00:00Z])

    assert {:error, :invalid_work} =
             Memory.commit(storage, [
               {:insert_room, record},
               {:put_work, %{id: "bad", account_id: "support", status: :invalid}}
             ])

    assert {:ok, nil} = Memory.get_room(storage, record.id)
    assert {:ok, [^record]} = Memory.commit(storage, [{:insert_room, record}])
  end

  test "declarations and memberships use revision checks", %{storage: storage} do
    declaration = Declaration.new!(%{room_id: "room/state", definition_key: "team"})
    assert {:ok, ^declaration} = Memory.insert_room_declaration(storage, declaration)
    assert {:ok, [^declaration]} = Memory.list_room_declarations(storage)
    assert {:ok, stopped} = Declaration.set_desired(declaration, :stopped)

    assert {:error, :room_declaration_conflict} =
             Memory.update_room_declaration(storage, declaration.room_id, 2, stopped)

    assert {:ok, ^stopped} =
             Memory.update_room_declaration(storage, declaration.room_id, 1, stopped)

    membership = Membership.new!(%{room_id: declaration.room_id, member: "alice", issuer: "operator"})
    assert {:ok, ^membership} = Memory.insert_membership(storage, membership)
    assert {:ok, active} = Memory.list_memberships(storage, declaration.room_id, status: :active)
    assert active == [membership]
    assert {:ok, revoked} = Membership.transition(membership, :revoked, "alice")

    assert {:ok, ^revoked} =
             Memory.update_membership(
               storage,
               declaration.room_id,
               membership.member_key,
               1,
               revoked
             )

    assert {:error, :membership_conflict} =
             Memory.update_membership(
               storage,
               declaration.room_id,
               membership.member_key,
               1,
               revoked
             )

    assert {:ok, :ok} = Memory.delete_room_declaration(storage, declaration.room_id, 2)
  end

  test "membership keys normalize Agent Addresses before hashing" do
    address = Jido.Agent.Address.new!(%{namespace: "test", partition: "workers", id: "member"})
    membership = Membership.new!(%{room_id: "room/address", member: address})

    assert Membership.key(address) == membership.member_key
    assert Membership.key(Jido.Agent.Address.to_map!(address)) == membership.member_key
  end

  test "history is immutable, ordered, and bounded", %{storage: storage} do
    records =
      for sequence <- 1..3 do
        signal = history_signal("message-#{sequence}", sequence, if(sequence == 2, do: "thread", else: nil))

        HistoryRecord.new!(%{
          room_id: "room/history",
          message_id: signal.id,
          sequence: sequence,
          thread_id: get_in(signal.data, ["message", "thread_id"]),
          signal: signal
        })
      end

    for record <- Enum.reverse(records), do: assert({:ok, ^record} = Memory.insert_history(storage, record))

    assert {:ok, ^records} = Memory.list_history(storage, "room/history")
    assert {:ok, [first, second]} = Memory.list_history(storage, "room/history", limit: 2)
    assert [first.sequence, second.sequence] == [1, 2]
    assert {:ok, [second, third]} = Memory.list_history(storage, "room/history", latest: true, limit: 2)
    assert [second.sequence, third.sequence] == [2, 3]
    assert {:ok, [thread]} = Memory.list_history(storage, "room/history", thread_id: "thread")
    assert thread.sequence == 2
    assert {:ok, [^first]} = Memory.list_history(storage, "room/history", before: "message-2")
    assert {:ok, [^third]} = Memory.list_history(storage, "room/history", after: "message-2")

    assert {:error, :invalid_options} =
             Memory.list_history(storage, "room/history", before: "message-2", after: "message-1")

    changed = %{hd(records) | signal: history_signal("message-1", 1, nil, "different")}
    assert {:error, :message_id_conflict} = Memory.insert_history(storage, changed)
    assert {:ok, 3} = Memory.last_history_sequence(storage, "room/history")
  end

  test "reactions use stable identity, revision checks, and bounded queries", %{storage: storage} do
    first = reaction("message-a", "eyes", "alice")
    second = reaction("message-a", "thumbsup", "bob")
    third = reaction("message-b", "eyes", "alice")

    assert {:ok, ^third} = Memory.insert_reaction(storage, third)
    assert {:ok, ^second} = Memory.insert_reaction(storage, second)
    assert {:ok, ^first} = Memory.insert_reaction(storage, first)
    assert {:ok, ^first} = Memory.insert_reaction(storage, first)

    assert {:ok, [^first, ^second, ^third]} = Memory.list_reactions(storage, "room/reactions")
    assert {:ok, [^first, ^second]} = Memory.list_reactions(storage, "room/reactions", message_id: "message-a")

    assert {:ok, [^first, ^second, ^third]} =
             Memory.list_reactions(storage, "room/reactions", message_ids: ["message-a", "message-b"])

    assert {:ok, [^second, ^third]} = Memory.list_reactions(storage, "room/reactions", after: first.id)
    assert {:ok, [^first]} = Memory.list_reactions(storage, "room/reactions", limit: 1)

    assert {:ok, ^first} =
             Memory.get_reaction(storage, first.room_id, first.message_id, first.reaction, first.actor_key)

    assert {:ok, removed} = Reaction.transition(first, :removed)

    assert {:error, :reaction_conflict} =
             Memory.update_reaction(
               storage,
               first.room_id,
               first.message_id,
               first.reaction,
               first.actor_key,
               2,
               removed
             )

    assert {:ok, ^removed} =
             Memory.update_reaction(
               storage,
               first.room_id,
               first.message_id,
               first.reaction,
               first.actor_key,
               1,
               removed
             )

    assert {:ok, [^second, ^third]} = Memory.list_reactions(storage, "room/reactions", status: :active)
    assert {:ok, [^removed]} = Memory.list_reactions(storage, "room/reactions", status: :removed)

    assert {:error, :invalid_reaction_cursor} =
             Memory.list_reactions(storage, "room/reactions", after: "missing")

    assert {:error, :invalid_options} =
             Memory.list_reactions(storage, "room/reactions", message_id: "a", message_ids: ["a"])

    assert {:error, :invalid_options} =
             Memory.list_reactions(storage, "room/reactions", message_ids: Enum.map(1..101, &"message-#{&1}"))

    assert {:error, :invalid_options} = Memory.list_reactions(storage, "room/reactions", limit: 1_001)
  end

  test "Commit applies reaction changes atomically", %{storage: storage} do
    reaction = reaction("message-atomic", "eyes", "alice")

    assert {:error, :invalid_storage_command} =
             Memory.commit(storage, [
               {:insert_reaction, reaction},
               {:invalid_command, reaction}
             ])

    assert {:ok, nil} =
             Memory.get_reaction(
               storage,
               reaction.room_id,
               reaction.message_id,
               reaction.reaction,
               reaction.actor_key
             )

    assert {:ok, [^reaction]} = Memory.commit(storage, [{:insert_reaction, reaction}])
  end

  test "snapshot restore rejects invalid reaction indexes" do
    reaction = reaction("message-restore", "eyes", "alice")
    engine = %{Jido.Chat.Runtime.Storage.Engine.new() | reactions: %{{"wrong", "key", "shape", "value"} => reaction}}

    assert {:error, :invalid_storage_snapshot} = Jido.Chat.Runtime.Storage.Engine.restore(engine)

    corrupt = %{reaction | id: "changed"}
    key = {corrupt.room_id, corrupt.message_id, corrupt.reaction, corrupt.actor_key}
    engine = %{Jido.Chat.Runtime.Storage.Engine.new() | reactions: %{key => corrupt}}

    assert {:error, :invalid_storage_snapshot} = Jido.Chat.Runtime.Storage.Engine.restore(engine)
  end

  test "connection declarations are portable and use revision checks", %{storage: storage} do
    declaration =
      ConnectionDeclaration.new!(%{
        account_id: "support",
        definition_key: "test-provider",
        secret_refs: %{token: "vault://chat/support"},
        settings: %{poll_interval: 500},
        metadata: %{owner: :operations}
      })

    assert declaration.secret_refs == %{"token" => "vault://chat/support"}
    assert declaration.settings == %{"poll_interval" => 500}
    assert declaration.metadata == %{"owner" => "operations"}

    assert {:ok, ^declaration} =
             declaration |> ConnectionDeclaration.to_map() |> ConnectionDeclaration.from_map()

    assert {:ok, ^declaration} = Memory.insert_connection(storage, declaration)
    assert {:ok, [^declaration]} = Memory.list_connections(storage)
    assert {:ok, stopped} = ConnectionDeclaration.set_desired(declaration, :stopped)

    assert {:error, :connection_conflict} =
             Memory.update_connection(storage, declaration.account_id, 2, stopped)

    assert {:ok, ^stopped} =
             Memory.update_connection(storage, declaration.account_id, 1, stopped)

    assert {:error, :connection_conflict} =
             Memory.insert_connection(storage, %{declaration | metadata: %{"owner" => "other"}})
  end

  test "bindings enforce external identity and deterministic bounded queries", %{storage: storage} do
    first =
      Binding.new!(%{
        account_id: "support",
        room_id: "team",
        external_room_id: "provider-a",
        direction: :both
      })

    second =
      Binding.new!(%{
        account_id: "support",
        room_id: "team",
        external_room_id: "provider-b",
        direction: :outbound
      })

    assert {:ok, ^second} = Memory.insert_binding(storage, second)
    assert {:ok, ^first} = Memory.insert_binding(storage, first)
    assert {:ok, [^first, ^second]} = Memory.list_bindings(storage, "support")
    assert {:ok, [^second]} = Memory.list_bindings(storage, "support", after: "provider-a")
    assert {:ok, [^second]} = Memory.list_bindings(storage, "support", direction: :outbound)

    duplicate = %{first | room_id: "other"}
    assert {:error, :binding_conflict} = Memory.insert_binding(storage, duplicate)

    assert {:ok, disabled} = Binding.set_enabled(first, false)

    assert {:error, :binding_conflict} =
             Memory.update_binding(storage, "support", "provider-a", 2, disabled)

    assert {:ok, ^disabled} =
             Memory.update_binding(storage, "support", "provider-a", 1, disabled)

    assert {:ok, [^disabled]} = Memory.list_bindings(storage, "support", enabled: false)
    assert {:error, :invalid_options} = Memory.list_bindings(storage, "support", limit: 0)
  end

  test "Commit applies connection and binding commands atomically", %{storage: storage} do
    declaration =
      ConnectionDeclaration.new!(%{account_id: "atomic", definition_key: "provider"})

    binding =
      Binding.new!(%{
        account_id: "atomic",
        room_id: "team",
        external_room_id: "provider-room"
      })

    assert {:error, :invalid_storage_command} =
             Memory.commit(storage, [
               {:insert_connection, declaration},
               {:invalid_command, binding}
             ])

    assert {:ok, nil} = Memory.get_connection(storage, "atomic")

    assert {:ok, [^declaration, ^binding]} =
             Memory.commit(storage, [
               {:insert_connection, declaration},
               {:insert_binding, binding}
             ])
  end

  defp room(id, kind, inserted_at) do
    Record.new!(%{
      id: id,
      kind: kind,
      name: id,
      inserted_at: inserted_at,
      updated_at: inserted_at
    })
  end

  defp reaction(message_id, value, actor) do
    Reaction.new!(%{
      room_id: "room/reactions",
      message_id: message_id,
      reaction: value,
      actor: actor,
      inserted_at: ~U[2026-11-16 10:00:00Z],
      updated_at: ~U[2026-11-16 10:00:00Z]
    })
  end

  defp history_signal(id, sequence, thread_id, text \\ nil) do
    Jido.Chat.Runtime.Signal.Room.Message.new!(
      %{
        "room" => Jido.Agent.Address.new!(%{namespace: "test", id: "room/history"}),
        "sequence" => sequence,
        "author" => "alice",
        "message" =>
          Jido.Chat.Message.to_map(
            Jido.Chat.Message.new(%{
              id: id,
              room_id: "room/history",
              thread_id: thread_id,
              actor: Jido.Chat.Runtime.Room.actor("alice"),
              content: [Jido.Chat.Content.text(text || id)]
            })
          ),
        "mentions" => []
      },
      id: id
    )
  end
end
