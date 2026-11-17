defmodule Jido.Chat.RuntimeStorageDetsTest do
  use ExUnit.Case, async: false

  alias Jido.Chat.Runtime.Bridge.Binding
  alias Jido.Chat.Runtime.Connection.Declaration, as: ConnectionDeclaration
  alias Jido.Chat.Runtime.Room.{Declaration, HistoryRecord, Membership, Reaction, Record}
  alias Jido.Chat.Runtime.Storage

  alias Jido.Chat.Runtime.Storage.{
    Bindings,
    Commit,
    Connections,
    Dets,
    Engine,
    Links,
    Outbox,
    Reactions,
    Rooms
  }

  @table :jido_chat_runtime_storage_dets_test
  @snapshot_key :jido_chat_runtime_snapshot
  @history_key :jido_chat_runtime_history

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

    assert :ok =
             Storage.validate(
               {Dets, storage},
               [Links, Outbox, Reactions, Rooms, Connections, Bindings, Commit]
             )

    assert Dets.format_version() == 6

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

    declaration = Declaration.new!(%{room_id: room.id, definition_key: "support"})
    membership = Membership.new!(%{room_id: room.id, member: "alice", issuer: "operator"})
    history = history(room.id)

    reaction =
      Reaction.new!(%{
        room_id: room.id,
        message_id: history.message_id,
        reaction: "eyes",
        actor: "alice"
      })

    connection =
      ConnectionDeclaration.new!(%{
        account_id: "support",
        definition_key: "provider",
        secret_refs: %{"token" => "vault://support"}
      })

    binding =
      Binding.new!(%{
        account_id: "support",
        room_id: room.id,
        external_room_id: "provider-room"
      })

    assert {:ok, ^declaration} = Dets.insert_room_declaration(storage, declaration)
    assert {:ok, ^membership} = Dets.insert_membership(storage, membership)
    assert {:ok, ^history} = Dets.insert_history(storage, history)
    assert {:ok, ^reaction} = Dets.insert_reaction(storage, reaction)
    assert {:ok, ^connection} = Dets.insert_connection(storage, connection)
    assert {:ok, ^binding} = Dets.insert_binding(storage, binding)

    stop_storage()
    assert_split_history(path, history)
    restored = start_storage(path)

    assert {:ok, ^link} = Dets.link_for_local(restored, "support", "local-1")

    assert {:ok, ^link} =
             Dets.link_for_external(restored, "support", "provider-room", "provider-message")

    assert {:ok, ^work} = Dets.get_work(restored, "work-1")
    assert {:ok, ^room} = Dets.get_room(restored, room.id)
    assert {:ok, [^room]} = Dets.list_rooms(restored, kind: :group)
    assert {:ok, ^declaration} = Dets.get_room_declaration(restored, room.id)
    assert {:ok, [^membership]} = Dets.list_memberships(restored, room.id)
    assert {:ok, [^history]} = Dets.list_history(restored, room.id)
    assert {:ok, [^reaction]} = Dets.list_reactions(restored, room.id)
    assert {:ok, ^connection} = Dets.get_connection(restored, connection.account_id)
    assert {:ok, [^binding]} = Dets.list_bindings(restored, connection.account_id)
  end

  test "a version 3 snapshot moves history into separate records", %{path: path} do
    history = history("room/v3")
    assert {:ok, ^history, engine} = Engine.command(Engine.new(), {:insert_history, history})

    assert {:ok, @table} =
             :dets.open_file(@table,
               file: String.to_charlist(path),
               type: :set,
               auto_save: :infinity
             )

    assert :ok = :dets.insert(@table, {@snapshot_key, 3, engine})
    assert :ok = :dets.sync(@table)
    assert :ok = :dets.close(@table)

    storage = start_storage(path)
    assert {:ok, [^history]} = Dets.list_history(storage, history.room_id)
    stop_storage()
    assert_split_history(path, history)

    restored = start_storage(path)
    assert {:ok, [^history]} = Dets.list_history(restored, history.room_id)
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
    assert {:ok, [^link]} = Dets.links_for_local(storage, "support", "local-v1")
    assert {:ok, ^work} = Dets.get_work(storage, "work-v1")
    assert {:ok, []} = Dets.list_rooms(storage)
    assert {:ok, []} = Dets.list_connections(storage)
    assert {:ok, []} = Dets.list_bindings(storage, "support")
    assert {:ok, []} = Dets.list_reactions(storage, "room/none")

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

  test "a version 2 snapshot keeps Room records and gains empty runtime state", %{path: path} do
    room =
      Record.new!(%{
        id: "room/v2",
        kind: :group,
        inserted_at: ~U[2026-11-16 10:00:00Z],
        updated_at: ~U[2026-11-16 10:00:00Z]
      })

    assert {:ok, ^room, engine} = Engine.command(Engine.new(), {:insert_room, room})
    version_2_engine = Map.drop(engine, [:room_declarations, :memberships, :history])

    assert {:ok, @table} =
             :dets.open_file(@table,
               file: String.to_charlist(path),
               type: :set,
               auto_save: :infinity
             )

    assert :ok = :dets.insert(@table, {@snapshot_key, 2, version_2_engine})
    assert :ok = :dets.sync(@table)
    assert :ok = :dets.close(@table)

    storage = start_storage(path)
    assert {:ok, ^room} = Dets.get_room(storage, room.id)
    assert {:ok, []} = Dets.list_room_declarations(storage)
    assert {:ok, []} = Dets.list_memberships(storage, room.id)
    assert {:ok, []} = Dets.list_history(storage, room.id)
    assert {:ok, []} = Dets.list_reactions(storage, room.id)
  end

  test "a version 5 snapshot gains an empty reaction projection", %{path: path} do
    history = history("room/v5")
    assert {:ok, ^history, engine} = Engine.command(Engine.new(), {:insert_history, history})
    version_5_engine = Map.delete(engine, :reactions)

    assert {:ok, @table} =
             :dets.open_file(@table,
               file: String.to_charlist(path),
               type: :set,
               auto_save: :infinity
             )

    assert :ok = :dets.insert(@table, {@snapshot_key, 5, version_5_engine})
    assert :ok = :dets.sync(@table)
    assert :ok = :dets.close(@table)

    storage = start_storage(path)
    assert {:ok, [^history]} = Dets.list_history(storage, history.room_id)
    assert {:ok, []} = Dets.list_reactions(storage, history.room_id)
  end

  defp start_storage(path) do
    start_supervised!({Dets, table: @table, path: path})
  end

  defp stop_storage do
    assert :ok = stop_supervised({Dets, @table})
  end

  defp assert_split_history(path, history) do
    room_id = history.room_id
    message_id = history.message_id

    assert {:ok, @table} =
             :dets.open_file(@table,
               file: String.to_charlist(path),
               type: :set,
               auto_save: :infinity
             )

    assert [{@snapshot_key, 6, engine}] = :dets.lookup(@table, @snapshot_key)
    assert engine.history == %{}

    assert [{{@history_key, ^room_id, ^message_id}, ^history}] =
             :dets.lookup(@table, {@history_key, room_id, message_id})

    assert :ok = :dets.close(@table)
  end

  defp history(room_id) do
    signal =
      Jido.Chat.Runtime.Signal.Room.Message.new!(
        %{
          "room" => Jido.Agent.Address.new!(%{namespace: "test", id: room_id}),
          "sequence" => 1,
          "author" => "alice",
          "message" =>
            Jido.Chat.Message.to_map(
              Jido.Chat.Message.new(%{
                id: "message-1",
                room_id: room_id,
                actor: Jido.Chat.Runtime.Room.actor("alice"),
                content: [Jido.Chat.Content.text("hello")]
              })
            ),
          "mentions" => []
        },
        id: "message-1"
      )

    HistoryRecord.new!(%{
      room_id: room_id,
      message_id: signal.id,
      sequence: 1,
      thread_id: nil,
      signal: signal
    })
  end
end
