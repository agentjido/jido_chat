defmodule Jido.Chat.RuntimeStorageTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Runtime.Room.{Declaration, HistoryRecord, Membership, Record}
  alias Jido.Chat.Runtime.Storage
  alias Jido.Chat.Runtime.Storage.{Adapter, Commit, Links, Memory, Outbox, Rooms}

  defmodule LinksOnly do
    use Adapter, capabilities: [Links]

    @impl Links
    def put_link(_resource, link), do: {:ok, link}

    @impl Links
    def link_for_local(_resource, _account_id, _local_id), do: {:ok, nil}

    @impl Links
    def link_for_external(_resource, _account_id, _room_id, _message_id), do: {:ok, nil}
  end

  defmodule CallbackOnly do
    def put_link(_resource, link), do: {:ok, link}
    def link_for_local(_resource, _account_id, _local_id), do: {:ok, nil}
    def link_for_external(_resource, _account_id, _room_id, _message_id), do: {:ok, nil}
  end

  defmodule FalseDeclaration do
    def __storage_capabilities__, do: [Links]
  end

  setup do
    start_supervised!(Memory)
    |> then(&%{storage: &1})
  end

  test "Memory implements every merge-scope capability", %{storage: storage} do
    assert :ok == Storage.validate({Memory, storage}, [Links, Outbox, Rooms, Commit])

    assert Storage.capabilities(Memory) == [
             Links,
             Outbox,
             Rooms,
             Jido.Chat.Runtime.Storage.RoomDeclarations,
             Jido.Chat.Runtime.Storage.Memberships,
             Jido.Chat.Runtime.Storage.History,
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

  test "links are available by local and provider identity", %{storage: storage} do
    link = %{
      account_id: "support",
      local_message_id: "local-1",
      external_room_id: "provider-room",
      external_message_id: "provider-1"
    }

    assert {:ok, ^link} = Memory.put_link(storage, link)
    assert {:ok, ^link} = Memory.link_for_local(storage, "support", "local-1")
    assert {:ok, ^link} = Memory.link_for_external(storage, "support", "provider-room", "provider-1")
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

  defp room(id, kind, inserted_at) do
    Record.new!(%{
      id: id,
      kind: kind,
      name: id,
      inserted_at: inserted_at,
      updated_at: inserted_at
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
