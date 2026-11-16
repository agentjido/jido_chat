defmodule Jido.Chat.RuntimeRoomRecordTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Runtime.Room.Record

  test "builds a portable Room record with stable defaults" do
    assert {:ok, record} =
             Record.new(%{
               kind: :group,
               name: "Support",
               metadata: %{"count" => 2, visibility: :private}
             })

    assert record.id =~ "room/"
    assert record.schema_version == 1
    assert record.kind == :group
    assert record.name == "Support"
    assert record.metadata == %{"visibility" => "private", "count" => 2}
    assert record.revision == 1
    assert record.inserted_at == record.updated_at
    assert record.inserted_at.utc_offset == 0
    assert record.inserted_at.std_offset == 0

    assert {:ok, ^record} = record |> Record.to_map() |> Record.from_map()
  end

  test "updates only public mutable fields and increments the revision" do
    inserted_at = ~U[2026-11-16 10:00:00.000000Z]

    record =
      Record.new!(%{
        id: "room/support",
        kind: :channel,
        name: "Support",
        inserted_at: inserted_at,
        updated_at: inserted_at
      })

    assert {:ok, updated} =
             Record.update(record, %{name: "Customer Support", metadata: %{tier: 1}})

    assert updated.id == record.id
    assert updated.kind == record.kind
    assert updated.inserted_at == record.inserted_at
    assert updated.revision == 2
    assert updated.name == "Customer Support"
    assert updated.metadata == %{"tier" => 1}
    assert DateTime.compare(updated.updated_at, record.updated_at) in [:eq, :gt]

    assert {:error, :invalid_room_update} = Record.update(record, %{kind: :direct})
    assert {:error, :invalid_room_update} = Record.update(record, %{})
  end

  test "rejects invalid identity, kind, timestamps, and metadata" do
    assert {:error, _reason} = Record.new(%{id: "", kind: :group})
    assert {:error, _reason} = Record.new(%{id: String.duplicate("x", 257), kind: :group})
    assert {:error, _reason} = Record.new(%{kind: :invalid})

    assert {:error, _reason} =
             Record.new(%{
               kind: :group,
               inserted_at: ~U[2026-11-16 10:00:01Z],
               updated_at: ~U[2026-11-16 10:00:00Z]
             })

    assert {:error, :invalid_room_record} =
             Record.new(%{kind: :group, metadata: %{pid: self()}})

    assert {:error, :invalid_room_record} =
             Record.new(%{kind: :group, metadata: %{:same => 1, "same" => 2}})
  end

  test "rejects lossy atom and string key collisions before normalization" do
    assert {:error, :invalid_room_record} =
             Record.new(%{"kind" => "group", kind: :direct})

    assert {:error, :invalid_room_record} =
             Record.new(%{"__type__" => "runtime_room_record", __type__: :room, kind: :group})

    record = Record.new!(%{kind: :group, name: "Support"})

    assert {:error, :invalid_room_update} =
             Record.update(record, %{"name" => "String", name: "Atom"})
  end
end
