defmodule Jido.Chat.RuntimeRoomRecordsTest do
  use ExUnit.Case, async: false

  alias Jido.Chat.Runtime.Storage.{Adapter, Links, Memory}

  defmodule StoredRuntime do
    use Jido.Chat.Runtime,
      jido: Jido.Chat.RuntimeRoomRecordsTest.Jido,
      storage: {Memory, Jido.Chat.RuntimeRoomRecordsTest.Storage}
  end

  defmodule NoStorageRuntime do
    use Jido.Chat.Runtime, jido: Jido.Chat.RuntimeRoomRecordsTest.NoStorageJido
  end

  defmodule LinksOnly do
    use Adapter, capabilities: [Links]

    @impl Links
    def put_link(_resource, link), do: {:ok, link}

    @impl Links
    def link_for_local(_resource, _account_id, _local_id), do: {:ok, nil}

    @impl Links
    def link_for_external(_resource, _account_id, _room_id, _message_id), do: {:ok, nil}
  end

  defmodule UnsupportedRuntime do
    use Jido.Chat.Runtime,
      jido: Jido.Chat.RuntimeRoomRecordsTest.UnsupportedJido,
      storage: {LinksOnly, :resource}
  end

  setup do
    start_supervised!({Memory, name: Jido.Chat.RuntimeRoomRecordsTest.Storage})
    :ok
  end

  test "Runtime facade creates, queries, updates, and deletes Room records" do
    assert {:ok, room} =
             StoredRuntime.create_room(%{
               id: "room/support",
               kind: :group,
               name: "Support"
             })

    assert {:ok, ^room} = StoredRuntime.get_room(room.id)
    assert {:ok, [^room]} = StoredRuntime.list_rooms(kind: :group)

    assert {:ok, updated} = StoredRuntime.update_room(room.id, 1, %{name: "Help"})
    assert updated.revision == 2
    assert updated.name == "Help"

    assert {:error, :room_conflict} =
             StoredRuntime.update_room(room.id, 1, %{name: "Stale"})

    assert :ok = StoredRuntime.delete_room(room.id, 2)
    assert {:error, :not_found} = StoredRuntime.get_room(room.id)
    assert {:error, :not_found} = StoredRuntime.delete_room(room.id, 2)
    assert {:error, :not_found} = StoredRuntime.update_room(room.id, 2, %{name: "Gone"})
  end

  test "Runtime facade requires a Rooms-capable storage selection" do
    assert {:error, :room_storage_required} =
             NoStorageRuntime.create_room(%{kind: :group})

    assert {:error, :unsupported_storage_capability} =
             UnsupportedRuntime.create_room(%{kind: :group})
  end
end
