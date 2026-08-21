defmodule Jido.Chat.ConcurrencyTest do
  use ExUnit.Case, async: true

  alias Jido.Chat
  alias Jido.Chat.{Concurrency, Incoming, MessageContext, Response}

  defmodule TestAdapter do
    use Jido.Chat.Adapter

    @impl true
    def channel_type, do: :test

    @impl true
    def transform_incoming(payload), do: {:ok, Incoming.new(payload)}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok,
       Response.new(%{
         external_message_id: "sent-1",
         external_room_id: room_id,
         channel_type: :test
       })}
    end
  end

  test "normalizes bounded concurrency configuration" do
    assert %Concurrency{
             strategy: :burst,
             debounce_ms: 250,
             max_queue_size: 3,
             queue_entry_ttl_ms: 2_000,
             overflow_policy: :drop_newest,
             lock_scope: :channel,
             max_concurrent: 2
           } =
             Concurrency.new(%{
               "strategy" => "burst",
               "debounceMs" => 250,
               "maxQueueSize" => 3,
               "queueEntryTtlMs" => 2_000,
               "onQueueFull" => "drop-newest",
               "lockScope" => "channel",
               "maxConcurrent" => 2
             })
  end

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

  test "release excludes expired pending entries and records deterministic expiry events" do
    chat =
      Chat.new()
      |> Chat.configure_concurrency(strategy: :queue, queue_entry_ttl_ms: 10)

    assert {:acquired, chat} =
             Chat.acquire_lock(chat, "thread:release-expiry", "owner-1", now_ms: 0)

    assert {:queued, chat} =
             Chat.acquire_lock(chat, "thread:release-expiry", "owner-2",
               now_ms: 1,
               metadata: %{message: %{id: "m2"}}
             )

    assert {{:released, []}, chat} =
             Chat.release_lock(chat, "thread:release-expiry", "owner-1", now_ms: 12)

    assert %{event: :expired, owner: "owner-2", at: 12, expired_at: 11} =
             List.last(Chat.concurrency_events(chat))
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

  test "burst drains the latest message with ordered skipped context" do
    chat =
      Chat.new()
      |> Chat.configure_concurrency(
        strategy: :burst,
        debounce_ms: 100,
        max_queue_size: 3,
        queue_entry_ttl_ms: 1_000
      )

    assert {:bursting, chat} =
             Chat.acquire_lock(chat, "thread:burst", "owner-1",
               now_ms: 0,
               metadata: %{message: %{id: "m1", text: "one"}}
             )

    assert {:queued, chat} =
             Chat.acquire_lock(chat, "thread:burst", "owner-2",
               now_ms: 10,
               metadata: %{message: %{id: "m2", text: "two"}}
             )

    assert {:queued, chat} =
             Chat.acquire_lock(chat, "thread:burst", "owner-3",
               now_ms: 20,
               metadata: %{message: %{id: "m3", text: "three"}}
             )

    assert {{:waiting, %{remaining_ms: 1}}, ^chat} =
             Chat.drain_lock(chat, "thread:burst", "owner-1", now_ms: 119)

    assert {{:drained, drained}, chat} =
             Chat.drain_lock(chat, "thread:burst", "owner-1", now_ms: 120)

    assert drained.owner == "owner-3"
    assert drained.metadata.message.id == "m3"

    assert %MessageContext{
             skipped: [%{id: "m1"}, %{id: "m2"}],
             total_since_last_handler: 3,
             total_count: 3
           } = drained.context

    assert %{locks: %{}, pending_locks: %{}} = Chat.lock_snapshot(chat)

    assert Enum.map(Chat.concurrency_events(chat), & &1.event) == [
             :queued,
             :queued,
             :queued,
             :drained
           ]

    assert %{event: :drained, message_id: "m3", skipped_count: 2, total_count: 3} =
             List.last(Chat.concurrency_events(chat))
  end

  test "each accepted burst entry resets the idle deadline" do
    chat =
      Chat.new()
      |> Chat.configure_concurrency(strategy: :burst, debounce_ms: 100)

    assert {:bursting, chat} = burst(chat, "owner-1", "m1", 0)
    assert {:queued, chat} = burst(chat, "owner-2", "m2", 90)

    assert {{:waiting, %{remaining_ms: 90}}, ^chat} =
             Chat.drain_lock(chat, "thread:overflow", "owner-1", now_ms: 100)

    assert {{:waiting, %{remaining_ms: 1}}, ^chat} =
             Chat.drain_lock(chat, "thread:overflow", "owner-1", now_ms: 189)

    assert {{:drained, drained}, _chat} =
             Chat.drain_lock(chat, "thread:overflow", "owner-1", now_ms: 190)

    assert drained.metadata.message.id == "m2"
    assert Enum.map(drained.context.skipped, & &1.id) == ["m1"]
  end

  test "bounded burst overflow can drop the oldest entry" do
    chat =
      Chat.new()
      |> Chat.configure_concurrency(
        strategy: :burst,
        debounce_ms: 0,
        max_queue_size: 2,
        overflow_policy: :drop_oldest
      )

    assert {:bursting, chat} = burst(chat, "owner-1", "m1", 0)
    assert {:queued, chat} = burst(chat, "owner-2", "m2", 1)
    assert {:queued, chat} = burst(chat, "owner-3", "m3", 2)

    assert {{:drained, drained}, chat} =
             Chat.drain_lock(chat, "thread:overflow", "owner-1", now_ms: 2)

    assert Enum.map(drained.context.skipped, & &1.id) == ["m2"]
    assert drained.metadata.message.id == "m3"

    assert %{event: :dropped, owner: "owner-1", message_id: "m1", reason: :queue_full} =
             Enum.find(Chat.concurrency_events(chat), &(&1.event == :dropped))
  end

  test "bounded queue overflow can drop the newest entry" do
    chat =
      Chat.new()
      |> Chat.configure_concurrency(
        strategy: :queue,
        max_queue_size: 1,
        overflow_policy: :drop_newest
      )

    assert {:acquired, chat} = Chat.acquire_lock(chat, "thread:newest", "owner-1", now_ms: 0)

    assert {:queued, chat} =
             Chat.acquire_lock(chat, "thread:newest", "owner-2",
               now_ms: 1,
               metadata: %{message: %{id: "m2"}}
             )

    assert {:dropped, chat} =
             Chat.acquire_lock(chat, "thread:newest", "owner-3",
               now_ms: 2,
               metadata: %{message: %{id: "m3"}}
             )

    assert {{:drained, drained}, _chat} =
             Chat.drain_lock(chat, "thread:newest", "owner-1", now_ms: 2)

    assert drained.owner == "owner-2"
    assert drained.metadata.message.id == "m2"
  end

  test "drain discards expired entries with deterministic metadata" do
    chat =
      Chat.new()
      |> Chat.configure_concurrency(strategy: :burst, debounce_ms: 0, queue_entry_ttl_ms: 10)

    assert {:bursting, chat} = burst(chat, "owner-1", "m1", 0)
    assert {:queued, chat} = burst(chat, "owner-2", "m2", 15)

    assert {{:drained, drained}, chat} =
             Chat.drain_lock(chat, "thread:overflow", "owner-1", now_ms: 20)

    assert drained.metadata.message.id == "m2"
    assert drained.context.total_count == 1

    assert %{event: :expired, owner: "owner-1", expired_at: 10} =
             Enum.find(Chat.concurrency_events(chat), &(&1.event == :expired))
  end

  test "debounce records superseded entries and drains only the latest" do
    chat = Chat.new() |> Chat.configure_concurrency(strategy: :debounce, debounce_ms: 50)

    assert {:acquired, chat} = Chat.acquire_lock(chat, "thread:debounce-meta", "owner-1", now_ms: 0)

    assert {:debounced, chat} =
             Chat.acquire_lock(chat, "thread:debounce-meta", "owner-2",
               now_ms: 10,
               metadata: %{message: %{id: "m2"}}
             )

    assert {:debounced, chat} =
             Chat.acquire_lock(chat, "thread:debounce-meta", "owner-3",
               now_ms: 20,
               metadata: %{message: %{id: "m3"}}
             )

    assert {{:waiting, _}, _chat} =
             Chat.drain_lock(chat, "thread:debounce-meta", "owner-1", now_ms: 69)

    assert {{:drained, drained}, chat} =
             Chat.drain_lock(chat, "thread:debounce-meta", "owner-1", now_ms: 70)

    assert drained.owner == "owner-3"
    assert drained.context == MessageContext.new(skipped: [], total_count: 1)

    assert %{event: :superseded, owner: "owner-2", superseded_by: "owner-3"} =
             Enum.find(Chat.concurrency_events(chat), &(&1.event == :superseded))
  end

  test "channel lock scope drains one conversation and retains the other with its deadline" do
    chat =
      Chat.new()
      |> Chat.configure_concurrency(strategy: :burst, debounce_ms: 100, lock_scope: :channel)

    assert {:bursting, chat} =
             Chat.acquire_lock(chat, "thread:one", "owner-1",
               channel_id: "channel:a",
               now_ms: 0,
               conversation_key: "thread:one",
               metadata: %{message: %{id: "m1"}}
             )

    assert {:queued, chat} =
             Chat.acquire_lock(chat, "thread:two", "owner-2",
               channel_id: "channel:a",
               now_ms: 10,
               conversation_key: "thread:two",
               metadata: %{message: %{id: "m2"}}
             )

    assert {:bursting, chat} =
             Chat.acquire_lock(chat, "thread:three", "owner-3",
               channel_id: "channel:b",
               now_ms: 1,
               metadata: %{message: %{id: "m3"}}
             )

    assert %{locks: locks} = Chat.lock_snapshot(chat)
    assert Map.keys(locks) |> Enum.sort() == ["channel:a", "channel:b"]

    assert {{:drained, first}, chat} =
             Chat.drain_lock(chat, "thread:one", "owner-1",
               channel_id: "channel:a",
               conversation_key: "thread:one",
               now_ms: 100
             )

    assert first.owner == "owner-1"
    assert first.context.skipped == []

    assert %{
             locks: %{
               "channel:a" => %{
                 owner: "owner-2",
                 conversation_key: "thread:two",
                 ready_at: 110
               }
             },
             pending_locks: %{"channel:a" => [%{owner: "owner-2"}]}
           } = Chat.lock_snapshot(chat)

    assert {{:waiting, %{remaining_ms: 1}}, ^chat} =
             Chat.drain_lock(chat, "thread:two", "owner-2",
               channel_id: "channel:a",
               conversation_key: "thread:two",
               now_ms: 109
             )

    assert {{:drained, second}, chat} =
             Chat.drain_lock(chat, "thread:two", "owner-2",
               channel_id: "channel:a",
               conversation_key: "thread:two",
               now_ms: 110
             )

    assert second.owner == "owner-2"
    assert %{locks: %{}, pending_locks: %{}} = Chat.lock_snapshot(chat)

    assert [first_event, second_event] =
             Chat.concurrency_events(chat)
             |> Enum.filter(&(&1.event == :drained))

    assert %{owner: "owner-1", conversation_key: "thread:one", drained_count: 1} = first_event
    assert %{owner: "owner-2", conversation_key: "thread:two", drained_count: 1} = second_event
  end

  test "channel-scoped debounce only supersedes entries in the same conversation" do
    chat =
      Chat.new()
      |> Chat.configure_concurrency(strategy: :debounce, debounce_ms: 50, lock_scope: :channel)

    assert {:acquired, chat} =
             Chat.acquire_lock(chat, "thread:one", "owner-1",
               channel_id: "channel:a",
               conversation_key: "thread:one",
               now_ms: 0
             )

    assert {:debounced, chat} =
             Chat.acquire_lock(chat, "thread:one", "owner-2",
               channel_id: "channel:a",
               conversation_key: "thread:one",
               now_ms: 10,
               metadata: %{message: %{id: "m2"}}
             )

    assert {:debounced, chat} =
             Chat.acquire_lock(chat, "thread:two", "owner-3",
               channel_id: "channel:a",
               conversation_key: "thread:two",
               now_ms: 20,
               metadata: %{message: %{id: "m3"}}
             )

    assert {:debounced, chat} =
             Chat.acquire_lock(chat, "thread:one", "owner-4",
               channel_id: "channel:a",
               conversation_key: "thread:one",
               now_ms: 30,
               metadata: %{message: %{id: "m4"}}
             )

    assert %{pending_locks: %{"channel:a" => pending}} = Chat.lock_snapshot(chat)
    assert Enum.map(pending, & &1.owner) == ["owner-3", "owner-4"]

    assert [%{owner: "owner-2", superseded_by: "owner-4", conversation_key: "thread:one"}] =
             Chat.concurrency_events(chat)
             |> Enum.filter(&(&1.event == :superseded))
  end

  test "concurrent strategy can bound active handlers per key" do
    chat =
      Chat.new()
      |> Chat.configure_concurrency(strategy: :concurrent, max_concurrent: 2)

    assert {:acquired, chat} = Chat.acquire_lock(chat, "thread:slots", "owner-1")
    assert {:acquired, chat} = Chat.acquire_lock(chat, "thread:slots", "owner-2")
    assert {:busy, chat} = Chat.acquire_lock(chat, "thread:slots", "owner-3")

    assert {{:released, []}, chat} = Chat.release_lock(chat, "thread:slots", "owner-1")
    assert {:acquired, _chat} = Chat.acquire_lock(chat, "thread:slots", "owner-3")
  end

  test "pending burst state survives serialization and old snapshots still load" do
    chat = Chat.new() |> Chat.configure_concurrency(strategy: :burst, debounce_ms: 100)
    assert {:bursting, chat} = burst(chat, "owner-1", "m1", 10)

    encoded = Chat.to_map(chat)
    revived = encoded |> Jason.encode!() |> Jason.decode!() |> Chat.from_map()

    assert encoded["concurrency_events"] != []

    assert {{:drained, drained}, _chat} =
             Chat.drain_lock(revived, "thread:overflow", "owner-1", now_ms: 110)

    assert drained.metadata["message"]["id"] == "m1"
    assert Enum.map(Chat.concurrency_events(revived), & &1.event) == [:queued]

    legacy = Chat.from_map(%{"id" => "legacy", "user_name" => "bot"})
    assert %{locks: %{}, pending_locks: %{}} = Chat.lock_snapshot(legacy)
    assert Chat.concurrency_events(legacy) == []
  end

  test "process_message passes optional drained context to context-aware handlers" do
    test_pid = self()
    context = MessageContext.new(skipped: [%{id: "m1"}], total_count: 2)

    chat =
      Chat.new(adapters: %{test: TestAdapter})
      |> Chat.on_new_mention(fn _chat, _thread, incoming, received_context ->
        send(test_pid, {:handled, incoming.external_message_id, received_context})
      end)

    incoming =
      Incoming.new(%{
        external_room_id: "room-1",
        external_message_id: "m2",
        text: "@bot hello",
        was_mentioned: true
      })

    assert {:ok, _chat, ^incoming} =
             Chat.process_message(chat, :test, "test:room-1", incoming, message_context: context)

    assert_received {:handled, "m2", ^context}
  end

  test "ordinary messages give context-aware mention handlers a default context" do
    assert_default_context_for_route(:mention)
  end

  test "ordinary messages give context-aware regex handlers a default context" do
    assert_default_context_for_route(:message)
  end

  test "ordinary messages give context-aware subscribed handlers a default context" do
    assert_default_context_for_route(:subscribed)
  end

  test "message context does not change the legacy stateful handler arguments" do
    test_pid = self()
    context = MessageContext.new(skipped: [%{id: "m1"}], total_count: 2)

    chat =
      Chat.new(adapters: %{test: TestAdapter})
      |> Chat.on_new_mention(fn received_chat, thread, incoming ->
        send(test_pid, {:legacy_handler, received_chat.id, thread.id, incoming.external_message_id})
      end)

    incoming =
      Incoming.new(%{
        external_room_id: "room-1",
        external_message_id: "m3",
        text: "@bot hello again",
        was_mentioned: true
      })

    assert {:ok, _chat, ^incoming} =
             Chat.process_message(chat, :test, "test:room-1", incoming, message_context: context)

    assert_received {:legacy_handler, chat_id, "test:room-1", "m3"}
    assert chat_id == chat.id
  end

  defp burst(chat, owner, message_id, now_ms) do
    Chat.acquire_lock(chat, "thread:overflow", owner,
      now_ms: now_ms,
      metadata: %{message: %{id: message_id}}
    )
  end

  defp assert_default_context_for_route(route) do
    test_pid = self()
    thread_id = "test:ordinary-#{route}"

    handler = fn received_chat, _thread, _incoming, context ->
      send(test_pid, {:ordinary_context, route, context})
      received_chat
    end

    chat =
      Chat.new(adapters: %{test: TestAdapter})
      |> register_route_handler(route, handler)
      |> maybe_subscribe(route, thread_id)

    incoming =
      Incoming.new(%{
        external_room_id: "ordinary-#{route}",
        external_message_id: "ordinary-#{route}",
        text: if(route == :message, do: "ping", else: "@bot hello"),
        was_mentioned: route == :mention
      })

    assert {:ok, _chat, ^incoming} = Chat.process_message(chat, :test, thread_id, incoming)

    assert_received {:ordinary_context, ^route, %MessageContext{} = context}
    assert context == MessageContext.new(skipped: [], total_count: 1)
  end

  defp register_route_handler(chat, :mention, handler), do: Chat.on_new_mention(chat, handler)

  defp register_route_handler(chat, :message, handler),
    do: Chat.on_new_message(chat, ~r/^ping$/, handler)

  defp register_route_handler(chat, :subscribed, handler),
    do: Chat.on_subscribed_message(chat, handler)

  defp maybe_subscribe(chat, :subscribed, thread_id), do: Chat.subscribe(chat, thread_id)
  defp maybe_subscribe(chat, _route, _thread_id), do: chat
end
