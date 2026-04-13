defmodule Jido.Chat.SerializationTest do
  use ExUnit.Case, async: true

  alias Jido.Chat

  alias Jido.Chat.{
    Attachment,
    CapabilityMatrix,
    ChannelRef,
    EventEnvelope,
    FileUpload,
    IngressResult,
    Message,
    ModalResult,
    PostPayload,
    Response,
    SentMessage,
    StreamChunk,
    Thread,
    WebhookRequest,
    WebhookResponse
  }

  defmodule WrappedStateAdapter do
    @behaviour Jido.Chat.StateAdapter

    alias Jido.Chat.StateAdapters.Memory

    @impl true
    def init(snapshot, opts), do: {:wrapped, Memory.init(snapshot, opts)}

    @impl true
    def snapshot({:wrapped, state}), do: Memory.snapshot(state)

    @impl true
    def subscribed?({:wrapped, state}, thread_id), do: Memory.subscribed?(state, thread_id)

    @impl true
    def subscribe({:wrapped, state}, thread_id),
      do: {:wrapped, Memory.subscribe(state, thread_id)}

    @impl true
    def unsubscribe({:wrapped, state}, thread_id),
      do: {:wrapped, Memory.unsubscribe(state, thread_id)}

    @impl true
    def thread_state({:wrapped, state}, thread_id), do: Memory.thread_state(state, thread_id)

    @impl true
    def put_thread_state({:wrapped, state}, thread_id, value),
      do: {:wrapped, Memory.put_thread_state(state, thread_id, value)}

    @impl true
    def channel_state({:wrapped, state}, channel_id), do: Memory.channel_state(state, channel_id)

    @impl true
    def put_channel_state({:wrapped, state}, channel_id, value),
      do: {:wrapped, Memory.put_channel_state(state, channel_id, value)}

    @impl true
    def duplicate?({:wrapped, state}, key), do: Memory.duplicate?(state, key)

    @impl true
    def mark_dedupe({:wrapped, state}, key, limit),
      do: {:wrapped, Memory.mark_dedupe(state, key, limit)}
  end

  test "chat serialization is JSON-safe and explicitly non-serializable for handlers" do
    chat =
      Chat.new(
        adapters: %{test: __MODULE__},
        metadata: %{env: :test},
        dedupe: MapSet.new([{:test, "m1"}]),
        dedupe_order: [{:test, "m1"}]
      )
      |> Chat.on_new_mention(fn _thread, _incoming -> :ok end)
      |> Chat.on_new_message(~r/^ping$/, fn _thread, _incoming -> :ok end)

    encoded = Chat.to_map(chat)

    assert encoded["__type__"] == "chat"
    assert encoded["state_adapter"] == "Elixir.Jido.Chat.StateAdapters.Memory"
    assert encoded["handlers"]["serializable"] == false
    assert encoded["handlers"]["counts"]["mention"] == 1
    assert encoded["handlers"]["counts"]["message"] == 1
    assert encoded["dedupe_order"] == [["test", "m1"]]

    revived = Chat.from_map(encoded)

    assert revived.id == chat.id
    assert revived.metadata == %{"env" => :test}
    assert revived.dedupe_order == [{:test, "m1"}]
    assert revived.handlers.mention == []
    assert revived.handlers.message == []
  end

  test "chat serialization preserves custom state adapter snapshots" do
    chat =
      Chat.new(
        adapters: %{test: __MODULE__},
        state_adapter: WrappedStateAdapter,
        subscriptions: ["test:room-1"],
        thread_state: %{"test:room-1" => %{phase: :open}}
      )
      |> Chat.subscribe("test:room-2")
      |> Chat.put_channel_state("test:chan-1", %{topic: "general"})

    encoded = Chat.to_map(chat)

    assert encoded["state_adapter"] == "Elixir.Jido.Chat.SerializationTest.WrappedStateAdapter"

    revived = Chat.from_map(encoded)

    assert revived.state_adapter == WrappedStateAdapter
    assert match?({:wrapped, _}, revived.state)
    assert Chat.subscribed?(revived, "test:room-1")
    assert Chat.subscribed?(revived, "test:room-2")
    assert Chat.thread_state(revived, "test:room-1") == %{"phase" => :open}
    assert Chat.channel_state(revived, "test:chan-1") == %{"topic" => "general"}
  end

  test "thread and channel refs round-trip with module adapters" do
    thread =
      Thread.new(%{
        id: "test:room-1",
        adapter_name: :test,
        adapter: __MODULE__,
        external_room_id: "room-1"
      })

    channel =
      ChannelRef.new(%{
        id: "test:room-1",
        adapter_name: :test,
        adapter: __MODULE__,
        external_id: "room-1"
      })

    thread_encoded = Thread.to_map(thread)
    channel_encoded = ChannelRef.to_map(channel)

    assert thread_encoded["adapter"] == "Elixir.Jido.Chat.SerializationTest"
    assert channel_encoded["adapter"] == "Elixir.Jido.Chat.SerializationTest"

    assert %Thread{adapter: __MODULE__, id: "test:room-1"} = Thread.from_map(thread_encoded)

    assert %ChannelRef{adapter: __MODULE__, id: "test:room-1"} =
             ChannelRef.from_map(channel_encoded)
  end

  test "message and sent message round-trip" do
    message =
      Message.new(%{
        id: "m1",
        thread_id: "test:room-1",
        external_room_id: "room-1",
        external_message_id: "m1",
        text: "hello"
      })

    sent =
      SentMessage.new(%{
        id: "m1",
        thread_id: "test:room-1",
        adapter: __MODULE__,
        external_room_id: "room-1",
        text: "hello",
        attachments: [%{path: "/tmp/report.pdf", media_type: "application/pdf"}],
        response: Response.new(%{external_message_id: "m1", external_room_id: "room-1"})
      })

    assert %Message{id: "m1", text: "hello"} = message |> Message.to_map() |> Message.from_map()

    assert %SentMessage{id: "m1", adapter: __MODULE__} =
             sent |> SentMessage.to_map() |> SentMessage.from_map()

    assert %SentMessage{attachments: [%Attachment{filename: "report.pdf"}]} =
             sent |> SentMessage.to_map() |> SentMessage.from_map()
  end

  test "file upload, stream chunk, and post payload round-trip" do
    payload =
      PostPayload.new(%{
        kind: :card,
        card: %{title: "Card"},
        fallback_text: "Card fallback",
        files: [%{path: "/tmp/report.pdf", media_type: "application/pdf"}],
        stream: ["hello", %{kind: :status, text: "working"}]
      })

    assert %FileUpload{filename: "report.pdf"} =
             %{path: "/tmp/report.pdf", media_type: "application/pdf"}
             |> FileUpload.normalize()
             |> FileUpload.to_map()
             |> FileUpload.from_map()

    assert %StreamChunk{kind: :status, text: "working"} =
             StreamChunk.new(%{kind: :status, text: "working"})
             |> StreamChunk.to_map()
             |> StreamChunk.from_map()

    assert %PostPayload{
             kind: :card,
             fallback_text: "Card fallback",
             files: [%FileUpload{filename: "report.pdf"}]
           } = payload |> PostPayload.to_map() |> PostPayload.from_map()
  end

  test "event and webhook structs round-trip" do
    envelope =
      EventEnvelope.new(%{
        adapter_name: :test,
        event_type: :message,
        payload: %{external_room_id: "room-1", text: "hello"},
        metadata: %{source: "webhook"}
      })

    request =
      WebhookRequest.new(%{
        adapter_name: :test,
        headers: %{"X-Test" => "1"},
        payload: %{external_room_id: "room-1"}
      })

    response = WebhookResponse.new(%{status: 202, body: %{ok: true}})
    matrix = CapabilityMatrix.new(%{adapter_name: :test, capabilities: %{send_message: :native}})
    modal_result = ModalResult.new(%{id: "modal_1", external_room_id: "room-1"})

    ingress_result =
      IngressResult.new(%{
        chat: Chat.new(adapters: %{test: __MODULE__}),
        adapter_name: :test,
        event: envelope,
        response: response,
        request: request,
        mode: :request
      })

    assert %EventEnvelope{event_type: :message} =
             envelope |> EventEnvelope.to_map() |> EventEnvelope.from_map()

    assert %WebhookRequest{headers: %{"x-test" => "1"}} =
             request |> WebhookRequest.to_map() |> WebhookRequest.from_map()

    assert %WebhookResponse{status: 202} =
             response |> WebhookResponse.to_map() |> WebhookResponse.from_map()

    assert %CapabilityMatrix{capabilities: %{send_message: :native}} =
             matrix |> CapabilityMatrix.to_map() |> CapabilityMatrix.from_map()

    assert %ModalResult{id: "modal_1"} =
             modal_result |> ModalResult.to_map() |> ModalResult.from_map()

    assert %IngressResult{adapter_name: :test, mode: :request} =
             ingress_result |> IngressResult.to_map() |> IngressResult.from_map()
  end

  test "chat reviver supports all typed payloads" do
    reviver = Chat.reviver()

    assert %Message{} =
             reviver.(
               Message.new(%{external_room_id: "room", external_message_id: "m1", text: "hi"})
               |> Message.to_map()
             )

    assert %SentMessage{} =
             reviver.(
               SentMessage.new(%{
                 id: "m1",
                 thread_id: "test:room",
                 adapter: __MODULE__,
                 external_room_id: "room",
                 response: Response.new(%{external_message_id: "m1", external_room_id: "room"})
               })
               |> SentMessage.to_map()
             )

    assert %EventEnvelope{} =
             reviver.(
               EventEnvelope.new(%{adapter_name: :test, event_type: :message, payload: %{}})
               |> EventEnvelope.to_map()
             )

    assert %IngressResult{} =
             reviver.(
               IngressResult.new(%{
                 chat: Chat.new(adapters: %{test: __MODULE__}),
                 adapter_name: :test,
                 event:
                   EventEnvelope.new(%{adapter_name: :test, event_type: :message, payload: %{}}),
                 response: WebhookResponse.accepted(),
                 request: WebhookRequest.new(%{adapter_name: :test, payload: %{}}),
                 mode: :request
               })
               |> IngressResult.to_map()
             )

    assert %CapabilityMatrix{} =
             reviver.(
               CapabilityMatrix.new(%{
                 adapter_name: :test,
                 capabilities: %{send_message: :native}
               })
               |> CapabilityMatrix.to_map()
             )

    assert %WebhookRequest{} =
             reviver.(
               WebhookRequest.new(%{adapter_name: :test, headers: %{}, payload: %{}})
               |> WebhookRequest.to_map()
             )

    assert %WebhookResponse{} =
             reviver.(WebhookResponse.accepted() |> WebhookResponse.to_map())

    assert %ModalResult{} =
             reviver.(ModalResult.new(%{id: "modal_1"}) |> ModalResult.to_map())
  end
end
