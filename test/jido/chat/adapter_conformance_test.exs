defmodule Jido.Chat.AdapterConformanceTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{Adapter, CapabilityMatrix, EventEnvelope, Incoming, Response, WebhookRequest}

  defmodule GoodAdapter do
    use Adapter

    @impl true
    def channel_type, do: :good

    @impl true
    def transform_incoming(payload), do: {:ok, Incoming.new(payload)}

    @impl true
    def send_message(room_id, text, _opts) do
      {:ok,
       Response.new(%{
         external_message_id: "m1",
         external_room_id: room_id,
         metadata: %{text: text}
       })}
    end

    @impl true
    def capabilities do
      %{
        send_message: :native,
        edit_message: :unsupported,
        delete_message: :unsupported,
        fetch_messages: :unsupported,
        verify_webhook: :fallback,
        parse_event: :fallback,
        format_webhook_response: :fallback
      }
    end
  end

  defmodule BadAdapter do
    use Adapter

    @impl true
    def channel_type, do: :bad

    @impl true
    def transform_incoming(payload), do: {:ok, Incoming.new(payload)}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok, Response.new(%{external_message_id: "m1", external_room_id: room_id})}
    end

    @impl true
    def capabilities do
      %{
        send_message: :native,
        edit_message: :native
      }
    end
  end

  test "capability matrix struct normalizes statuses" do
    matrix = Adapter.capability_matrix(GoodAdapter)

    assert %CapabilityMatrix{} = matrix
    assert matrix.adapter_name == :good
    assert matrix.capabilities.send_message == :native
  end

  test "capability declarations are validated against callbacks" do
    assert :ok = Adapter.validate_capabilities(GoodAdapter)

    assert {:error, {:invalid_capability_matrix, mismatches}} =
             Adapter.validate_capabilities(BadAdapter)

    assert {:edit_message, :missing_callback} in mismatches
  end

  test "unsupported callbacks return deterministic unsupported error" do
    assert {:error, :unsupported} = Adapter.edit_message(GoodAdapter, "room", "msg", "text", [])
    assert {:error, :unsupported} = Adapter.delete_message(GoodAdapter, "room", "msg", [])
  end

  test "default webhook parse path yields typed message envelope" do
    request =
      WebhookRequest.new(%{
        adapter_name: :good,
        payload: %{
          external_room_id: "room-1",
          external_user_id: "user-1",
          external_message_id: "msg-1",
          text: "hello"
        }
      })

    assert {:ok, %EventEnvelope{} = envelope} = Adapter.parse_event(GoodAdapter, request, [])
    assert envelope.event_type == :message
    assert %Incoming{external_message_id: "msg-1"} = envelope.payload
  end
end
