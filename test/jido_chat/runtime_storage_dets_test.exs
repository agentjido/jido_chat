defmodule Jido.Chat.RuntimeStorageDetsTest do
  use ExUnit.Case, async: false

  alias Jido.Chat.Runtime.Room.Record
  alias Jido.Chat.Runtime.Storage
  alias Jido.Chat.Runtime.Storage.{Commit, Dets, Engine, Links, Outbox, Rooms}

  @table :jido_chat_runtime_storage_dets_test
  @snapshot_key :jido_chat_runtime_snapshot

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "jido-chat-storage-#{System.unique_integer([:positive, :monotonic])}.dets"
      )

    on_exit(fn ->
      _ = :dets.close(@table)
      _ = File.rm(path)
    end)

    %{path: path}
  end

  test "Dets retains all Runtime storage capabilities across restart", %{path: path} do
    storage = start_storage(path)
    assert :ok = Storage.validate({Dets, storage}, [Links, Outbox, Rooms, Commit])
    assert Dets.format_version() == 2

    link = %{
      account_id: "support",
      local_message_id: "local-1",
      external_room_id: "provider-room",
      external_message_id: "provider-message"
    }

    work = %{id: "work-1", account_id: "support", status: :pending, payload: %{}}

    room =
      Record.new!(%{
        id: "room/support",
        kind: :group,
        inserted_at: ~U[2026-11-16 10:00:00Z],
        updated_at: ~U[2026-11-16 10:00:00Z]
      })

    assert {:ok, ^link} = Dets.put_link(storage, link)
    assert {:ok, ^work} = Dets.put_work(storage, work)
    assert {:ok, ^room} = Dets.insert_room(storage, room)

    stop_storage()
    restored = start_storage(path)

    assert {:ok, ^link} = Dets.link_for_local(restored, "support", "local-1")

    assert {:ok, ^link} =
             Dets.link_for_external(restored, "support", "provider-room", "provider-message")

    assert {:ok, ^work} = Dets.get_work(restored, "work-1")
    assert {:ok, ^room} = Dets.get_room(restored, room.id)
    assert {:ok, [^room]} = Dets.list_rooms(restored, kind: :group)
  end

  test "a failed durable Commit leaves no partial state", %{path: path} do
    storage = start_storage(path)

    link = %{
      account_id: "support",
      local_message_id: "local-atomic",
      external_room_id: "provider-room",
      external_message_id: "provider-atomic"
    }

    assert {:error, :invalid_work} =
             Dets.commit(storage, [
               {:put_link, link},
               {:put_work, %{id: "bad", account_id: "support", status: :invalid}}
             ])

    stop_storage()
    restored = start_storage(path)
    assert {:ok, nil} = Dets.link_for_local(restored, "support", "local-atomic")
  end

  test "an unsupported snapshot version fails closed and preserves the file", %{path: path} do
    assert {:ok, @table} =
             :dets.open_file(@table,
               file: String.to_charlist(path),
               type: :set,
               auto_save: :infinity
             )

    assert :ok = :dets.insert(@table, {@snapshot_key, 99, %{}})
    assert :ok = :dets.sync(@table)
    assert :ok = :dets.close(@table)

    previous = Process.flag(:trap_exit, true)

    assert {:error, {:unsupported_storage_version, 99}} =
             Dets.start_link(table: @table, path: path)

    Process.flag(:trap_exit, previous)

    assert File.exists?(path)
  end

  test "a version 1 snapshot keeps existing data and gains an empty Room catalog", %{path: path} do
    link = %{
      account_id: "support",
      local_message_id: "local-v1",
      external_room_id: "provider-room",
      external_message_id: "provider-v1"
    }

    work = %{id: "work-v1", account_id: "support", status: :pending}

    assert {:ok, ^link, engine} = Engine.command(Engine.new(), {:put_link, link})
    assert {:ok, ^work, engine} = Engine.command(engine, {:put_work, work})
    version_1_engine = Map.delete(engine, :rooms)

    assert {:ok, @table} =
             :dets.open_file(@table,
               file: String.to_charlist(path),
               type: :set,
               auto_save: :infinity
             )

    assert :ok = :dets.insert(@table, {@snapshot_key, 1, version_1_engine})
    assert :ok = :dets.sync(@table)
    assert :ok = :dets.close(@table)

    storage = start_storage(path)
    assert {:ok, ^link} = Dets.link_for_local(storage, "support", "local-v1")
    assert {:ok, ^work} = Dets.get_work(storage, "work-v1")
    assert {:ok, []} = Dets.list_rooms(storage)

    room =
      Record.new!(%{
        id: "room/after-v1",
        kind: :channel,
        inserted_at: ~U[2026-11-16 10:00:00Z],
        updated_at: ~U[2026-11-16 10:00:00Z]
      })

    assert {:ok, ^room} = Dets.insert_room(storage, room)
    stop_storage()
    restored = start_storage(path)

    assert {:ok, ^link} = Dets.link_for_local(restored, "support", "local-v1")
    assert {:ok, ^work} = Dets.get_work(restored, "work-v1")
    assert {:ok, ^room} = Dets.get_room(restored, room.id)
  end

  defp start_storage(path) do
    start_supervised!({Dets, table: @table, path: path})
  end

  defp stop_storage do
    assert :ok = stop_supervised({Dets, @table})
  end
end
