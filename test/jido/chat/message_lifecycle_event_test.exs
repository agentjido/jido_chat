defmodule Jido.Chat.MessageLifecycleEventTest do
  use ExUnit.Case, async: true

  alias Jido.Chat

  alias Jido.Chat.{
    Author,
    ChannelRef,
    EventEnvelope,
    EventNormalizer,
    Message,
    MessageDeletedEvent,
    MessageUpdatedEvent,
    Thread
  }

  defmodule TestAdapter do
    use Jido.Chat.Adapter

    @impl true
    def transform_incoming(payload), do: {:ok, Jido.Chat.Incoming.new(payload)}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok,
       Jido.Chat.Response.new(%{
         external_message_id: "sent-1",
         external_room_id: room_id,
         channel_type: :test
       })}
    end
  end

  defmodule LifecycleRequestAdapter do
    use Jido.Chat.Adapter

    @impl true
    def transform_incoming(payload), do: {:ok, Jido.Chat.Incoming.new(payload)}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok,
       Jido.Chat.Response.new(%{
         external_message_id: "sent-1",
         external_room_id: room_id,
         channel_type: :test
       })}
    end

    @impl true
    def parse_event(%Jido.Chat.WebhookRequest{payload: payload}, _opts) do
      {:ok,
       Jido.Chat.EventEnvelope.new(%{
         event_type: :message_updated,
         channel_id: "request:C1",
         thread_id: "request:C1:T1",
         message_id: payload["message_id"],
         payload: %{
           message_id: payload["message_id"],
           message: %{
             id: payload["message_id"],
             external_message_id: payload["message_id"],
             text: payload["text"]
           }
         }
       })}
    end
  end

  test "typed lifecycle events keep provider context and optional content" do
    author = Author.new(%{user_id: "U1", user_name: "casey"})

    message =
      Message.new(%{
        id: "M1",
        external_message_id: "M1",
        external_room_id: "C1",
        text: "corrected text"
      })

    updated =
      MessageUpdatedEvent.new(%{
        adapter_name: :slack,
        channel_id: "slack:C1",
        thread_id: "slack:C1:T1",
        message_id: "M1",
        message: message,
        author: author,
        timestamp: "2026-08-20T12:00:00Z",
        metadata: %{delivery_id: "D1"},
        raw: %{"type" => "message_changed"}
      })

    assert updated.message.text == "corrected text"
    assert updated.author == author
    assert updated.timestamp == "2026-08-20T12:00:00Z"
    assert updated.metadata == %{delivery_id: "D1"}
    assert updated.raw == %{"type" => "message_changed"}

    deleted =
      MessageDeletedEvent.new(%{
        adapter_name: :slack,
        channel_id: "slack:C1",
        thread_id: "slack:C1:T1",
        message_id: "M1",
        author: author,
        timestamp: "2026-08-20T12:01:00Z",
        raw: %{"type" => "message_deleted"}
      })

    assert deleted.message_id == "M1"
    assert deleted.message == nil
    assert deleted.author == author
  end

  test "normalizer creates lifecycle structs from adapter maps" do
    assert {:ok, %MessageUpdatedEvent{} = updated} =
             EventNormalizer.ensure_message_updated_event(
               %{
                 "channel_id" => "slack:C1",
                 "thread_id" => "slack:C1:T1",
                 "message_id" => "M1",
                 "message" => %{
                   "id" => "M1",
                   "external_message_id" => "M1",
                   "text" => "edited"
                 },
                 "author" => %{"user_id" => "U1", "user_name" => "casey"},
                 "timestamp" => "2026-08-20T12:00:00Z",
                 "metadata" => %{"delivery_id" => "D1"},
                 "raw" => %{"provider" => "slack"}
               },
               :slack
             )

    assert updated.adapter_name == :slack
    assert updated.message.text == "edited"
    assert updated.author.user_id == "U1"

    assert {:ok, %MessageDeletedEvent{} = deleted} =
             EventNormalizer.ensure_message_deleted_event(
               %{
                 message_id: "M1",
                 channel_id: "discord:C1",
                 thread_id: "discord:C1:T1",
                 raw: %{"provider" => "discord"}
               },
               :discord
             )

    assert deleted.adapter_name == :discord
    assert deleted.message == nil

    assert {:error, {:invalid_message_updated_event, :bad}} =
             EventNormalizer.ensure_message_updated_event(:bad, :slack)

    assert {:error, {:invalid_message_deleted_event, :bad}} =
             EventNormalizer.ensure_message_deleted_event(:bad, :slack)

    assert {:error, {:invalid_message_updated_event, %{}}} =
             EventNormalizer.ensure_message_updated_event(%{}, :slack)

    assert {:error, {:invalid_message_deleted_event, %{}}} =
             EventNormalizer.ensure_message_deleted_event(%{}, :slack)

    assert {:ok, %EventEnvelope{event_type: :message_updated}} =
             EventNormalizer.ensure_event_envelope(%{payload: updated}, :slack)
  end

  test "lifecycle envelopes and top-level reviver restore typed payloads" do
    thread =
      Thread.new(%{
        id: "test:C1:T1",
        adapter_name: :test,
        adapter: TestAdapter,
        external_room_id: "C1",
        external_thread_id: "T1"
      })

    channel =
      ChannelRef.new(%{
        id: "test:C1",
        adapter_name: :test,
        adapter: TestAdapter,
        external_id: "C1"
      })

    events = [
      {:message_updated,
       MessageUpdatedEvent.new(%{
         message_id: "M1",
         channel_id: "test:C1",
         thread_id: "test:C1:T1",
         thread: thread,
         channel: channel,
         message: %{id: "M1", external_message_id: "M1", text: "edited"}
       })},
      {:message_deleted,
       MessageDeletedEvent.new(%{
         message_id: "M2",
         channel_id: "test:C1",
         thread_id: "test:C1:T1",
         thread: thread,
         channel: channel
       })}
    ]

    for {event_type, payload} <- events do
      envelope =
        EventEnvelope.new(%{
          adapter_name: :test,
          event_type: event_type,
          payload: payload,
          raw: %{"delivery" => "D1"}
        })

      assert %EventEnvelope{event_type: ^event_type, payload: revived_payload} =
               envelope |> EventEnvelope.to_map() |> EventEnvelope.from_map()

      assert revived_payload.__struct__ == payload.__struct__
      assert revived_payload.message_id == payload.message_id
      assert %Thread{adapter: TestAdapter} = revived_payload.thread
      assert %ChannelRef{adapter: TestAdapter} = revived_payload.channel
      assert {:ok, %Jido.Chat.SentMessage{}} = Thread.post(revived_payload.thread, "thread reply")
      assert {:ok, %Jido.Chat.SentMessage{}} = ChannelRef.post(revived_payload.channel, "channel reply")

      assert Chat.reviver().(payload.__struct__.to_map(payload)).__struct__ == payload.__struct__
    end
  end

  test "lifecycle events preserve explicit and nested provider message ids" do
    nested_id_event =
      MessageUpdatedEvent.new(%{
        message: %{id: "M-from-message", text: "edited"}
      })

    assert nested_id_event.message_id == "M-from-message"
    assert nested_id_event.message.external_message_id == "M-from-message"

    nested_external_id_event =
      MessageUpdatedEvent.new(%{
        message: %{external_message_id: "M-from-provider", text: "edited"}
      })

    assert nested_external_id_event.message_id == "M-from-provider"

    explicit_id_event =
      MessageUpdatedEvent.new(%{
        message_id: "M-explicit",
        message: %{text: "edited"}
      })

    assert explicit_id_event.message_id == "M-explicit"
  end

  test "message update rejects nested content without a provider message id" do
    assert_missing_provider_id_rejected(:message_updated, :invalid_message_updated_event)
  end

  test "message delete rejects nested content without a provider message id" do
    assert_missing_provider_id_rejected(:message_deleted, :invalid_message_deleted_event)
  end

  test "lifecycle handlers route separately from normal message handlers" do
    chat =
      Chat.new(adapters: %{test: TestAdapter})
      |> Chat.on_new_message(~r/.*/, fn _thread, _incoming -> send(self(), :normal_message) end)
      |> Chat.on_message_updated(fn chat, event ->
        send(self(), {:updated, event})
        %{chat | metadata: Map.put(chat.metadata, :updated, true)}
      end)
      |> Chat.on_message_deleted(fn event -> send(self(), {:deleted, event}) end)

    update_envelope =
      EventEnvelope.new(%{
        adapter_name: :test,
        event_type: :message_updated,
        channel_id: "test:C1",
        thread_id: "test:C1:T1",
        message_id: "M1",
        payload: %{
          message: %{id: "M1", external_message_id: "M1", text: "edited"}
        },
        metadata: %{delivery_id: "D1"},
        raw: %{"provider_event" => "changed"}
      })

    assert {:ok, updated_chat, %EventEnvelope{payload: %MessageUpdatedEvent{} = updated}} =
             Chat.process_event(chat, :test, update_envelope, [])

    assert updated_chat.metadata.updated
    assert %ChannelRef{id: "test:C1"} = updated.channel
    assert %Thread{id: "test:C1:T1"} = updated.thread
    assert updated.adapter == TestAdapter
    assert updated.metadata == %{delivery_id: "D1"}
    assert updated.raw == %{"provider_event" => "changed"}
    assert_received {:updated, ^updated}
    refute_received :normal_message

    delete_envelope =
      EventEnvelope.new(%{
        adapter_name: :test,
        event_type: :message_deleted,
        payload: %{
          channel_id: "test:C1",
          thread_id: "test:C1:T1",
          message_id: "M1"
        }
      })

    assert {:ok, _chat, %EventEnvelope{payload: %MessageDeletedEvent{} = deleted}} =
             Chat.process_event(updated_chat, :test, delete_envelope, [])

    assert deleted.message == nil
    assert %ChannelRef{} = deleted.channel
    assert %Thread{} = deleted.thread
    assert_received {:deleted, ^deleted}
    refute_received :normal_message
  end

  test "lifecycle payload context overrides duplicate envelope metadata and raw values" do
    chat =
      Chat.new(adapters: %{test: TestAdapter})
      |> Chat.on_message_updated(fn event -> send(self(), {:merged, event}) end)

    envelope =
      EventEnvelope.new(%{
        adapter_name: :test,
        event_type: :message_updated,
        channel_id: "test:C1",
        thread_id: "test:C1:T1",
        message_id: "M1",
        payload: %{
          message: %{id: "M1", text: "edited"},
          metadata: %{payload_only: true, shared: :payload},
          raw: %{"payload_only" => true, "shared" => "payload"}
        },
        metadata: %{envelope_only: true, shared: :envelope},
        raw: %{"envelope_only" => true, "shared" => "envelope"}
      })

    assert {:ok, _chat, %EventEnvelope{payload: %MessageUpdatedEvent{} = updated}} =
             Chat.process_event(chat, :test, envelope, [])

    assert updated.metadata == %{envelope_only: true, payload_only: true, shared: :payload}

    assert updated.raw == %{
             "envelope_only" => true,
             "payload_only" => true,
             "shared" => "payload"
           }

    assert_received {:merged, ^updated}
  end

  test "request ingress dispatches parsed lifecycle events without normal message handlers" do
    chat =
      Chat.new(adapters: %{request: LifecycleRequestAdapter})
      |> Chat.on_new_message(~r/.*/, fn _thread, _incoming -> send(self(), :normal_message) end)
      |> Chat.on_message_updated(fn event -> send(self(), {:request_updated, event}) end)

    assert {:ok, _chat, %EventEnvelope{payload: %MessageUpdatedEvent{} = updated}, response} =
             Chat.handle_webhook_request(
               chat,
               :request,
               %{"message_id" => "M-request", "text" => "edited through request ingress"},
               []
             )

    assert updated.message_id == "M-request"
    assert updated.message.text == "edited through request ingress"
    assert response.status == 200
    assert_received {:request_updated, ^updated}
    refute_received :normal_message
  end

  test "lifecycle registration accepts chat values with the legacy handler map" do
    chat = Chat.new(adapters: %{test: TestAdapter})

    legacy_chat =
      %{chat | handlers: Map.drop(chat.handlers, [:message_updated, :message_deleted])}

    registered =
      legacy_chat
      |> Chat.on_message_updated(fn _event -> :ok end)
      |> Chat.on_message_deleted(fn _event -> :ok end)

    assert length(registered.handlers.message_updated) == 1
    assert length(registered.handlers.message_deleted) == 1
  end

  defp assert_missing_provider_id_rejected(event_type, error_tag) do
    chat = Chat.new(adapters: %{test: TestAdapter})

    envelope =
      EventEnvelope.new(%{
        adapter_name: :test,
        event_type: event_type,
        payload: %{message: %{text: "content without a provider id"}}
      })

    assert {:error, {^error_tag, rejected_payload}} =
             Chat.process_event(chat, :test, envelope, [])

    assert rejected_payload.message == %{text: "content without a provider id"}
  end
end
