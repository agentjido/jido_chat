defmodule Jido.Chat.SerializationTest do
  use ExUnit.Case, async: true

  alias Jido.Chat

  alias Jido.Chat.{
    CapabilityMatrix,
    ChannelRef,
    EventEnvelope,
    Message,
    ModalResult,
    Response,
    SentMessage,
    Thread,
    WebhookRequest,
    WebhookResponse
  }

  test "chat serialization is JSON-safe and explicitly non-serializable for handlers" do
    chat =
      Chat.new(adapters: %{test: __MODULE__}, metadata: %{env: :test})
      |> Chat.on_new_mention(fn _thread, _incoming -> :ok end)
      |> Chat.on_new_message(~r/^ping$/, fn _thread, _incoming -> :ok end)

    encoded = Chat.to_map(chat)

    assert encoded["__type__"] == "chat"
    assert encoded["handlers"]["serializable"] == false
    assert encoded["handlers"]["counts"]["mention"] == 1
    assert encoded["handlers"]["counts"]["message"] == 1

    revived = Chat.from_map(encoded)

    assert revived.id == chat.id
    assert revived.metadata == %{"env" => :test}
    assert revived.handlers.mention == []
    assert revived.handlers.message == []
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
        response: Response.new(%{external_message_id: "m1", external_room_id: "room-1"})
      })

    assert %Message{id: "m1", text: "hello"} = message |> Message.to_map() |> Message.from_map()

    assert %SentMessage{id: "m1", adapter: __MODULE__} =
             sent |> SentMessage.to_map() |> SentMessage.from_map()
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
