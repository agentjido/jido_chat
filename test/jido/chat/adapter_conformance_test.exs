defmodule Jido.Chat.AdapterConformanceTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{
    Adapter,
    CapabilityMatrix,
    EventEnvelope,
    FileUpload,
    Incoming,
    Message,
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

  defmodule InvalidCapabilityStatusAdapter do
    use Adapter

    @impl true
    def channel_type, do: :invalid_capability_status

    @impl true
    def transform_incoming(payload), do: {:ok, Incoming.new(payload)}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok, Response.new(%{external_message_id: "m1", external_room_id: room_id})}
    end

    @impl true
    def capabilities, do: %{send_message: :sometimes}
  end

  defmodule InvalidCapabilityMapAdapter do
    use Adapter

    @impl true
    def channel_type, do: :invalid_capability_map

    @impl true
    def transform_incoming(payload), do: {:ok, Incoming.new(payload)}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok, Response.new(%{external_message_id: "m1", external_room_id: room_id})}
    end

    @impl true
    def capabilities, do: [:send_message]
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

  defmodule FailingStreamAdapter do
    use Adapter

    @impl true
    def channel_type, do: :failing_stream

    @impl true
    def transform_incoming(payload), do: {:ok, Incoming.new(payload)}

    @impl true
    def send_message("send-failure", _text, _opts), do: {:error, :send_failed}

    def send_message(room_id, _text, _opts) do
      {:ok,
       Response.new(%{
         external_message_id: "msg_#{room_id}",
         external_room_id: room_id
       })}
    end

    @impl true
    def edit_message(_room_id, _message_id, _text, _opts), do: {:error, :edit_failed}

    @impl true
    def capabilities do
      %{
        send_message: :native,
        edit_message: :native,
        stream: :fallback
      }
    end
  end

  defmodule NilChannelTypeAdapter do
    use Adapter

    @impl true
    def channel_type, do: :nil_channel_type

    @impl true
    def transform_incoming(payload), do: {:ok, Incoming.new(payload)}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok,
       %Response{
         external_message_id: "m1",
         external_room_id: room_id,
         channel_type: nil
       }}
    end

    @impl true
    def capabilities do
      %{send_message: :native}
    end
  end

  defmodule MediaAdapter do
    use Adapter

    @impl true
    def channel_type, do: :media

    @impl true
    def transform_incoming(payload), do: {:ok, Incoming.new(payload)}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok, Response.new(%{external_message_id: "m1", external_room_id: room_id})}
    end

    @impl true
    def fetch_media("media://" <> file_id, _opts), do: {:ok, "bytes-" <> file_id}
    def fetch_media(_reference, _opts), do: {:error, :invalid_reference}

    @impl true
    def capabilities do
      %{send_message: :native, fetch_media: :native}
    end
  end

  defmodule MalformedMediaAdapter do
    use Adapter

    @impl true
    def channel_type, do: :malformed_media

    @impl true
    def transform_incoming(payload), do: {:ok, Incoming.new(payload)}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok, Response.new(%{external_message_id: "m1", external_room_id: room_id})}
    end

    @impl true
    def fetch_media(:wrapped, _opts), do: {:ok, %{bytes: "not-binary"}}
    def fetch_media(:invalid, _opts), do: :invalid

    @impl true
    def capabilities, do: %{send_message: :native, fetch_media: :native}
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

  test "capability validation rejects an invalid raw status before normalization" do
    assert {:error, {:invalid_capability_matrix, [send_message: :invalid_status]}} =
             Adapter.validate_capabilities(InvalidCapabilityStatusAdapter)
  end

  test "capability validation rejects a raw declaration that is not a map" do
    assert {:error, {:invalid_capability_matrix, [capabilities: :invalid_map]}} =
             Adapter.validate_capabilities(InvalidCapabilityMapAdapter)
  end

  test "fetch_media is optional and surfaces through the capability matrix" do
    assert Adapter.capability_matrix(MediaAdapter).capabilities.fetch_media == :native
    assert Adapter.capability_matrix(GoodAdapter).capabilities.fetch_media == :unsupported

    assert :ok = Adapter.validate_capabilities(MediaAdapter)
    assert {:ok, "bytes-42"} = Adapter.fetch_media(MediaAdapter, "media://42", [])
    assert {:error, :invalid_reference} = Adapter.fetch_media(MediaAdapter, "nope", [])
    assert {:error, :unsupported} = Adapter.fetch_media(GoodAdapter, "media://42", [])
  end

  test "fetch_media rejects malformed provider results" do
    assert {:error, :invalid_media_result} = Adapter.fetch_media(MalformedMediaAdapter, :wrapped, [])
    assert {:error, :invalid_media_result} = Adapter.fetch_media(MalformedMediaAdapter, :invalid, [])
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

  test "response normalization fills in a missing channel_type on response structs" do
    assert {:ok, %Response{} = response} =
             Adapter.send_message(NilChannelTypeAdapter, "room-4", "hello", [])

    assert response.channel_type == :nil_channel_type
    assert response.external_message_id == "m1"
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

  test "final stream fallback sends exact Markdown and rejects streams without visible text" do
    markdown = "Before **bold**\n\n| A |  | C |\n| --- | --- | --- |\n| 1 |  | 3 |"
    chunks = Jido.Chat.StreamMarkdownFixtures.one_character_chunks(markdown)

    assert Adapter.render_stream(chunks) == markdown

    assert {:ok, %Response{} = response} =
             Adapter.stream(FallbackAdapter, "room-final", chunks, fallback_mode: :final)

    assert response.metadata.text == markdown
    assert_received {:send_message, "room-final", ^markdown}

    assert {:error, :empty_stream} =
             Adapter.stream(FallbackAdapter, "room-empty", [], fallback_mode: :final)

    assert {:error, :empty_stream} =
             Adapter.stream(FallbackAdapter, "room-empty-edit", [],
               fallback_mode: :post_edit,
               placeholder_text: "working"
             )

    assert {:error, :empty_stream} =
             Adapter.stream(
               FallbackAdapter,
               "room-tool",
               [%{kind: :data, payload: %{tool: "search"}}],
               fallback_mode: :final
             )

    refute_received {:send_message, "room-empty", _text}
    refute_received {:send_message, "room-empty-edit", _text}
    refute_received {:send_message, "room-tool", _text}
  end

  test "post-edit fallback never sends or edits empty text" do
    assert {:ok, %Response{} = response} =
             Adapter.stream(
               FallbackAdapter,
               "room-visible",
               ["", "**", "done", "**"],
               fallback_mode: :post_edit,
               placeholder_text: "",
               update_every: 1
             )

    assert response.metadata.final_text == "**done**"

    assert_received {:send_message, "room-visible", first_text}
    assert String.trim(first_text) != ""

    edits =
      Stream.repeatedly(fn ->
        receive do
          {:edit_message, "room-visible", _message_id, text} -> {:ok, text}
        after
          0 -> :done
        end
      end)
      |> Enum.take_while(&(&1 != :done))
      |> Enum.map(fn {:ok, text} -> text end)

    assert Enum.all?(edits, &(String.trim(&1) != ""))
    assert List.last([first_text | edits]) == "**done**"
  end

  test "post-edit stream fallback returns send and edit failures" do
    assert {:error, :send_failed} =
             Adapter.stream(FailingStreamAdapter, "send-failure", ["content"],
               fallback_mode: :post_edit,
               placeholder_text: "working"
             )

    assert {:error, :edit_failed} =
             Adapter.stream(FailingStreamAdapter, "edit-failure", ["content"],
               fallback_mode: :post_edit,
               placeholder_text: "working"
             )
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

  test "legacy and trusted enriched inbound payloads use the same adapter callback" do
    legacy_payload = %{
      external_room_id: "room-legacy",
      external_user_id: "provider-user-1",
      external_message_id: "msg-legacy",
      text: "hello from an old adapter payload"
    }

    assert {:ok, %Incoming{} = legacy_incoming} = GoodAdapter.transform_incoming(legacy_payload)

    legacy_message = Message.from_incoming(legacy_incoming, adapter_name: :good)

    assert legacy_message.id == "msg-legacy"
    assert legacy_message.text == "hello from an old adapter payload"
    assert legacy_message.external_room_id == "room-legacy"
    assert legacy_message.author.user_id == "provider-user-1"
    assert legacy_message.author.id == nil
    assert legacy_message.external_reply_to_id == nil
    assert legacy_message.reply_context == nil

    enriched_payload = %{
      external_room_id: "room-enriched",
      external_user_id: "provider-user-2",
      external_message_id: "msg-enriched",
      text: "reply with trusted identity",
      author: %{
        id: "stable-user-2",
        user_id: "provider-user-2",
        user_name: "provider-name",
        full_name: "Provider Name"
      },
      external_reply_to_id: "msg-parent",
      reply_context: %{
        id: "parent-1",
        external_message_id: "msg-parent",
        text: "parent message",
        author: %{
          id: "stable-parent",
          user_id: "provider-parent",
          user_name: "parent-name"
        }
      }
    }

    assert {:ok, %Incoming{} = enriched_incoming} =
             GoodAdapter.transform_incoming(enriched_payload)

    enriched_message = Message.from_incoming(enriched_incoming, adapter_name: :good)

    assert enriched_message.author.id == "stable-user-2"
    assert enriched_message.author.user_id == "provider-user-2"
    assert enriched_message.external_reply_to_id == "msg-parent"
    assert enriched_message.reply_context.id == "parent-1"
    assert enriched_message.reply_context.author.id == "stable-parent"
  end
end
