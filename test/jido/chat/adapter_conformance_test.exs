defmodule Jido.Chat.AdapterConformanceTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{
    Adapter,
    CapabilityMatrix,
    EventEnvelope,
    FileUpload,
    Incoming,
    Modal,
    PostPayload,
    Response,
    WebhookRequest
  }

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

  defmodule FallbackAdapter do
    use Adapter

    @impl true
    def channel_type, do: :fallback

    @impl true
    def transform_incoming(payload), do: {:ok, Incoming.new(payload)}

    @impl true
    def send_message(room_id, text, _opts) do
      send(self(), {:send_message, room_id, text})

      {:ok,
       Response.new(%{
         external_message_id: "msg_#{room_id}",
         external_room_id: room_id,
         metadata: %{text: text}
       })}
    end

    @impl true
    def send_file(room_id, file, opts) do
      send(self(), {:send_file, room_id, file, opts})

      {:ok,
       Response.new(%{
         external_message_id: "file_#{room_id}",
         external_room_id: room_id,
         metadata: %{caption: Keyword.get(opts, :caption)}
       })}
    end

    @impl true
    def edit_message(room_id, message_id, text, _opts) do
      send(self(), {:edit_message, room_id, message_id, text})

      {:ok,
       Response.new(%{
         external_message_id: message_id,
         external_room_id: room_id,
         metadata: %{text: text}
       })}
    end

    @impl true
    def open_modal(room_id, payload, _opts) do
      send(self(), {:open_modal, room_id, payload})

      {:ok, %{id: "modal_#{room_id}", external_room_id: room_id, status: :opened}}
    end

    @impl true
    def capabilities do
      %{
        send_message: :native,
        send_file: :native,
        edit_message: :native,
        open_modal: :native,
        cards: :fallback,
        modals: :native,
        stream: :fallback,
        verify_webhook: :fallback,
        parse_event: :fallback,
        format_webhook_response: :fallback
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
    assert {:error, :unsupported} = Adapter.send_file(GoodAdapter, "room", "/tmp/test.png", [])
    assert {:error, :unsupported} = Adapter.edit_message(GoodAdapter, "room", "msg", "text", [])
    assert {:error, :unsupported} = Adapter.delete_message(GoodAdapter, "room", "msg", [])
    assert {:error, :unsupported} = Adapter.open_thread(GoodAdapter, "room", "msg", [])
  end

  test "post_message falls back to send_file for single-upload payloads" do
    payload =
      PostPayload.new(%{
        text: "caption",
        files: [%{path: "/tmp/demo.txt", filename: "demo.txt"}],
        metadata: %{scope: :conformance}
      })

    assert {:ok, %Response{external_message_id: "file_room-1"}} =
             Adapter.post_message(FallbackAdapter, "room-1", payload, [])

    assert_received {:send_file, "room-1", %FileUpload{} = upload, opts}
    assert upload.path == "/tmp/demo.txt"
    assert upload.filename == "demo.txt"
    assert Keyword.fetch!(opts, :caption) == "caption"
    assert Keyword.fetch!(opts, :metadata) == %{scope: :conformance}
  end

  test "stream fallback preserves structured chunks through placeholder plus edit" do
    assert {:ok, %Response{} = response} =
             Adapter.stream(
               FallbackAdapter,
               "room-2",
               [
                 "alpha",
                 %{kind: :step_start, payload: %{label: "Plan"}},
                 %{kind: :plan, payload: ["one"]}
               ],
               fallback_mode: :post_edit,
               placeholder_text: "working",
               update_every: 2
             )

    assert response.external_message_id == "msg_room-2"
    assert response.metadata.stream_fallback == :post_edit
    assert_received {:send_message, "room-2", "working"}
    assert_received {:edit_message, "room-2", "msg_room-2", intermediate_text}
    assert intermediate_text =~ "alpha"
    assert intermediate_text =~ "Plan"

    assert_received {:edit_message, "room-2", "msg_room-2", final_text}
    assert final_text =~ "alpha"
    assert final_text =~ "Plan"
    assert final_text =~ "- one"
  end

  test "typed card and modal helpers expose stable adapter-facing payloads" do
    assert %{"title" => "Status"} = Adapter.render_card(%{title: "Status"})

    assert {:ok, result} =
             Adapter.open_modal(
               FallbackAdapter,
               "room-3",
               Modal.new(%{callback_id: "deploy", title: "Deploy"}),
               []
             )

    assert result.id == "modal_room-3"
    assert_received {:open_modal, "room-3", payload}
    assert payload["callback_id"] == "deploy"
    assert payload["title"] == "Deploy"
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
