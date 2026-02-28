defmodule Jido.Chat.StructsTest do
  use ExUnit.Case, async: true

  alias Jido.Chat

  alias Jido.Chat.{
    ActionEvent,
    AssistantContextChangedEvent,
    AssistantThreadStartedEvent,
    CapabilityMatrix,
    ChannelInfo,
    ChannelMeta,
    EphemeralMessage,
    EventEnvelope,
    FetchOptions,
    Incoming,
    LegacyMessage,
    Media,
    Mention,
    Message,
    MessagePage,
    ModalResult,
    ModalCloseEvent,
    ModalSubmitEvent,
    Participant,
    PostPayload,
    Postable,
    ReactionEvent,
    Response,
    Room,
    SentMessage,
    SlashCommandEvent,
    ThreadPage,
    ThreadSummary,
    WebhookRequest,
    WebhookResponse
  }

  alias Jido.Chat.Content.{Audio, File, Image, Text, ToolResult, ToolUse, Video}

  describe "core structs" do
    test "Message.new/1 creates normalized message with defaults" do
      message =
        Message.new(%{external_room_id: "room_1", text: "hello", external_message_id: "m1"})

      assert message.id == "m1"
      assert message.channel_id == "room_1"
      assert message.external_room_id == "room_1"
      assert message.thread_id == nil
      assert message.text == "hello"
      assert message.formatted == "hello"
      assert message.attachments == []
      assert message.is_mention == false
    end

    test "LegacyMessage.new/1 remains available for migration" do
      message = LegacyMessage.new(%{room_id: "room_1", sender_id: "user_1", role: :user})
      assert message.room_id == "room_1"
      assert message.status == :sending
    end

    test "Room.new/1 creates room with defaults" do
      room = Room.new(%{type: :direct})

      assert String.starts_with?(room.id, "jch_")
      assert room.type == :direct
      assert room.external_bindings == %{}
      assert %DateTime{} = room.inserted_at
    end

    test "Participant.new/1 creates participant with defaults" do
      participant = Participant.new(%{type: :human})

      assert String.starts_with?(participant.id, "jch_")
      assert participant.presence == :offline
      assert participant.capabilities == [:text]
    end

    test "Incoming.new/1 normalizes mentions and media to named structs" do
      incoming =
        Incoming.new(%{
          external_room_id: "room_1",
          mentions: [%{user_id: "u1", username: "jane"}],
          media: [%{kind: :image, url: "telegram://file/abc"}],
          channel_meta: %{adapter_name: :telegram, external_room_id: "room_1"}
        })

      assert [%Mention{user_id: "u1", username: "jane"}] = incoming.mentions
      assert [%Media{kind: :image, url: "telegram://file/abc"}] = incoming.media

      assert %ChannelMeta{adapter_name: :telegram, external_room_id: "room_1"} =
               incoming.channel_meta
    end

    test "new typed structs normalize canonical bot-loop payloads" do
      fetch_options = FetchOptions.new(limit: 25, direction: :forward, cursor: "abc")
      assert fetch_options.limit == 25
      assert fetch_options.direction == :forward
      assert fetch_options.cursor == "abc"

      channel_info = ChannelInfo.new(%{id: "chan_1", name: "general", is_dm: false})
      assert channel_info.name == "general"

      message_page =
        MessagePage.new(%{
          messages: [%{external_room_id: "room_1", external_message_id: "m1", text: "hello"}],
          next_cursor: "next"
        })

      assert [%Message{external_message_id: "m1"}] = message_page.messages

      thread_summary =
        ThreadSummary.new(%{
          id: "thread_1",
          reply_count: 2,
          root_message: %{external_room_id: "room_1", external_message_id: "root", text: "root"}
        })

      assert %Message{external_message_id: "root"} = thread_summary.root_message

      thread_page = ThreadPage.new(%{threads: [thread_summary], next_cursor: nil})
      assert [^thread_summary] = thread_page.threads

      sent =
        SentMessage.new(%{
          id: "msg_1",
          thread_id: "test:room_1",
          adapter: __MODULE__,
          external_room_id: "room_1",
          response: Response.new(%{external_message_id: "msg_1", external_room_id: "room_1"})
        })

      assert sent.id == "msg_1"

      ephemeral =
        EphemeralMessage.new(%{id: "ep_1", thread_id: "test:room_1", used_fallback: true})

      assert ephemeral.used_fallback

      modal = ModalResult.new(%{id: "modal_1", status: :opened, external_room_id: "room_1"})
      assert modal.status == :opened

      payload = PostPayload.text("hello")
      assert payload.kind == :text
      assert payload.formatted == "hello"
    end

    test "Postable.to_payload/1 preserves encoding intent by kind" do
      text_payload = Postable.text("hello") |> Postable.to_payload()
      assert text_payload.text == "hello"
      assert text_payload.formatted == "hello"

      markdown_payload = Postable.markdown("**hello**") |> Postable.to_payload()
      assert markdown_payload.text == "**hello**"
      assert markdown_payload.metadata.format == :markdown

      raw_payload = Postable.raw(%{hello: "world"}) |> Postable.to_payload()
      assert raw_payload.raw == %{hello: "world"}
      assert is_binary(raw_payload.text)

      ast_payload = Postable.ast(%{node: :p}) |> Postable.to_payload()
      assert ast_payload.raw == %{node: :p}
      assert ast_payload.metadata.format == :ast

      card_payload = Postable.card(%{title: "Card"}) |> Postable.to_payload()
      assert card_payload.raw == %{title: "Card"}
      assert card_payload.metadata.format == :card
    end

    test "event placeholder structs parse cleanly" do
      assert %ReactionEvent{} = ReactionEvent.new(%{emoji: "👍", added: true})
      assert %ActionEvent{} = ActionEvent.new(%{action_id: "approve"})
      assert %ModalSubmitEvent{} = ModalSubmitEvent.new(%{callback_id: "form", values: %{a: "1"}})
      assert %ModalCloseEvent{} = ModalCloseEvent.new(%{callback_id: "form"})
      assert %SlashCommandEvent{} = SlashCommandEvent.new(%{command: "/help", text: "topic"})
      assert %AssistantThreadStartedEvent{} = AssistantThreadStartedEvent.new(%{thread_id: "t1"})

      assert %AssistantContextChangedEvent{} =
               AssistantContextChangedEvent.new(%{thread_id: "t1", context: %{a: 1}})
    end

    test "webhook/event/capability structs parse cleanly" do
      assert %CapabilityMatrix{} =
               CapabilityMatrix.new(%{
                 adapter_name: :telegram,
                 capabilities: %{send_message: :native, fetch_messages: :unsupported}
               })

      assert %WebhookRequest{} =
               WebhookRequest.new(%{
                 adapter_name: :telegram,
                 headers: %{"X-Test" => "1"},
                 payload: %{"message" => %{}}
               })

      assert %WebhookResponse{} = WebhookResponse.new(%{status: 200, body: %{ok: true}})

      assert %EventEnvelope{} =
               EventEnvelope.new(%{
                 adapter_name: :telegram,
                 event_type: :message,
                 payload: Incoming.new(%{external_room_id: "r1"})
               })
    end

    test "schema constructor errors raise Splode validation errors" do
      assert_raise Jido.Chat.Errors.Validation, fn ->
        Participant.new(%{})
      end
    end
  end

  describe "content blocks" do
    test "Text.new/1" do
      text = Text.new("hello")
      assert text.type == :text
      assert text.text == "hello"
    end

    test "Image.new/2 and from_base64/3" do
      image =
        Image.new("https://example.com/photo.jpg", media_type: "image/jpeg", alt_text: "photo")

      inline = Image.from_base64("base64==", "image/png", alt_text: "inline")

      assert image.url == "https://example.com/photo.jpg"
      assert image.media_type == "image/jpeg"
      assert inline.data == "base64=="
      assert inline.media_type == "image/png"
    end

    test "Audio.new/2 and from_base64/3" do
      audio = Audio.new("https://example.com/audio.mp3", duration: 12)
      inline = Audio.from_base64("base64==", "audio/ogg", duration: 2)

      assert audio.duration == 12
      assert inline.media_type == "audio/ogg"
    end

    test "Video.new/2 and from_base64/3" do
      video = Video.new("https://example.com/video.mp4", width: 640, height: 480)
      inline = Video.from_base64("base64==", "video/mp4", duration: 8)

      assert video.width == 640
      assert video.height == 480
      assert inline.duration == 8
    end

    test "File.new/3 and from_base64/4" do
      file = File.new("https://example.com/doc.pdf", "doc.pdf", media_type: "application/pdf")
      inline = File.from_base64("base64==", "a.txt", "text/plain", size: 7)

      assert file.filename == "doc.pdf"
      assert inline.size == 7
    end

    test "ToolUse.new/3 and ToolResult.new/3" do
      tool_use = ToolUse.new("call_1", "search", %{q: "elixir"})
      result = ToolResult.new("call_1", %{hits: 3})

      assert tool_use.type == :tool_use
      assert tool_use.name == "search"
      assert result.type == :tool_result
      assert result.is_error == false
    end
  end

  describe "event registration placeholders" do
    test "chat exposes registration functions for future event ingest" do
      chat =
        Chat.new()
        |> Chat.on_reaction(fn _event -> :ok end)
        |> Chat.on_action(fn _event -> :ok end)
        |> Chat.on_modal_submit(fn _event -> :ok end)
        |> Chat.on_modal_close(fn _event -> :ok end)
        |> Chat.on_slash_command(fn _event -> :ok end)

      assert length(chat.handlers.reaction) == 1
      assert length(chat.handlers.action) == 1
      assert length(chat.handlers.modal_submit) == 1
      assert length(chat.handlers.modal_close) == 1
      assert length(chat.handlers.slash_command) == 1
    end
  end
end
