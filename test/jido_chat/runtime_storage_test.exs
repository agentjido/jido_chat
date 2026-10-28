defmodule Jido.Chat.RuntimeStorageTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{Actor, Content, Message}
  alias Jido.Chat.Runtime.Storage
  alias Jido.Chat.Runtime.Storage.{Commit, History, Links, Memory, Outbox, Rooms}

  setup do
    start_supervised!(Memory)
    |> then(&%{storage: &1})
  end

  test "Memory implements every merge-scope capability", %{storage: storage} do
    assert :ok == Storage.validate({Memory, storage}, [History, Links, Outbox, Rooms, Commit])
  end

  test "history is ordered and append is idempotent", %{storage: storage} do
    first = message("message-1", "First")
    second = message("message-2", "Second")

    assert {:ok, ^first} = Memory.append_message(storage, first)
    assert {:ok, ^first} = Memory.append_message(storage, first)
    assert {:ok, ^second} = Memory.append_message(storage, second)
    assert {:ok, [^first, ^second]} = Memory.list_messages(storage, "room-1")
    assert {:ok, [^first]} = Memory.list_messages(storage, "room-1", limit: 1)

    changed = %{first | content: [Content.text("Changed")]}
    assert {:error, :message_conflict} = Memory.append_message(storage, changed)
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
    room = %{id: "room-1", title: "Support"}

    assert {:error, :invalid_work} =
             Memory.commit(storage, [
               {:put_room, room},
               {:put_work, %{id: "bad", account_id: "support", status: :invalid}}
             ])

    assert {:ok, nil} = Memory.get_room(storage, "room-1")

    assert {:ok, [^room, ["operator"]]} =
             Memory.commit(storage, [
               {:put_room, room},
               {:put_members, "room-1", ["operator"]}
             ])

    assert {:ok, ["operator"]} = Memory.get_members(storage, "room-1")
  end

  defp message(id, text) do
    Message.new(%{
      id: id,
      room_id: "room-1",
      actor: Actor.new(%{id: "operator", kind: :human}),
      content: [Content.text(text)]
    })
  end
end
