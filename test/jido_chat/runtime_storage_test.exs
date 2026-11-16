defmodule Jido.Chat.RuntimeStorageTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Runtime.Room.Record
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
    assert Storage.capabilities(Memory) == [Links, Outbox, Rooms, Commit]
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

  defp room(id, kind, inserted_at) do
    Record.new!(%{
      id: id,
      kind: kind,
      name: id,
      inserted_at: inserted_at,
      updated_at: inserted_at
    })
  end
end
