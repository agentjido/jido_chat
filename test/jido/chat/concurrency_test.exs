defmodule Jido.Chat.ConcurrencyTest do
  use ExUnit.Case, async: true

  alias Jido.Chat

  test "reject strategy blocks overlapping owners until release" do
    chat = Chat.new()

    assert {:acquired, chat} = Chat.acquire_lock(chat, "thread:1", "owner-1")
    assert {:busy, _chat} = Chat.acquire_lock(chat, "thread:1", "owner-2")

    assert {{:released, []}, chat} = Chat.release_lock(chat, "thread:1", "owner-1")
    assert {:acquired, _chat} = Chat.acquire_lock(chat, "thread:1", "owner-2")
  end

  test "queue strategy preserves pending owners in order" do
    chat = Chat.new() |> Chat.configure_concurrency(strategy: :queue)

    assert {:acquired, chat} = Chat.acquire_lock(chat, "thread:queue", "owner-1")

    assert {:queued, chat} =
             Chat.acquire_lock(chat, "thread:queue", "owner-2",
               concurrency: [strategy: :queue],
               metadata: %{message_id: "m2"}
             )

    assert {:queued, chat} =
             Chat.acquire_lock(chat, "thread:queue", "owner-3",
               concurrency: [strategy: :queue],
               metadata: %{message_id: "m3"}
             )

    assert {{:released, pending}, _chat} = Chat.release_lock(chat, "thread:queue", "owner-1")
    assert Enum.map(pending, & &1.owner) == ["owner-2", "owner-3"]
    assert Enum.map(pending, & &1.metadata.message_id) == ["m2", "m3"]
  end

  test "debounce strategy only keeps the latest pending owner" do
    chat = Chat.new() |> Chat.configure_concurrency(strategy: :debounce)

    assert {:acquired, chat} = Chat.acquire_lock(chat, "thread:debounce", "owner-1")

    assert {:debounced, chat} =
             Chat.acquire_lock(chat, "thread:debounce", "owner-2",
               concurrency: [strategy: :debounce],
               metadata: %{message_id: "m2"}
             )

    assert {:debounced, chat} =
             Chat.acquire_lock(chat, "thread:debounce", "owner-3",
               concurrency: [strategy: :debounce],
               metadata: %{message_id: "m3"}
             )

    assert {{:released, [%{owner: "owner-3", metadata: %{message_id: "m3"}}]}, _chat} =
             Chat.release_lock(chat, "thread:debounce", "owner-1")
  end

  test "concurrent strategy never stores locks" do
    chat = Chat.new() |> Chat.configure_concurrency(strategy: :concurrent)

    assert {:acquired, chat} =
             Chat.acquire_lock(chat, "thread:concurrent", "owner-1", concurrency: [strategy: :concurrent])

    assert {:acquired, chat} =
             Chat.acquire_lock(chat, "thread:concurrent", "owner-2", concurrency: [strategy: :concurrent])

    assert %{locks: %{}, pending_locks: %{}} = Chat.lock_snapshot(chat)
  end

  test "force release drains pending lock snapshots and serialization preserves state" do
    chat = Chat.new() |> Chat.configure_concurrency(strategy: :queue)

    assert {:acquired, chat} = Chat.acquire_lock(chat, "thread:force", "owner-1")

    assert {:queued, chat} =
             Chat.acquire_lock(chat, "thread:force", "owner-2", concurrency: [strategy: :queue])

    assert {{:released, [%{owner: "owner-2"}]}, chat} =
             Chat.force_release_lock(chat, "thread:force")

    encoded = Chat.to_map(chat)
    revived = Chat.from_map(encoded)

    assert encoded["pending_locks"] == %{}
    assert %{locks: %{}, pending_locks: %{}} = Chat.lock_snapshot(revived)
  end
end
