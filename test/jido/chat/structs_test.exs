defmodule Jido.Chat.StructsTest do
  use ExUnit.Case, async: true
  alias Jido.Chat

  alias Jido.Chat.{
    Attachment,
    FileUpload,
    Card,
    Media,
    Markdown,
    Message,
    Participant,
    PostPayload,
    Postable,
    Room,
    StreamChunk
  }

  alias Jido.Chat.Content.{Audio, File, Image, Text, ToolResult, ToolUse, Video}

  test "Message.new/1 creates normalized message with defaults" do
    message = Message.new(%{external_room_id: "room_1", text: "hello", external_message_id: "m1"})
    assert message.id == "m1"
    assert message.channel_id == "room_1"
    assert message.external_room_id == "room_1"
    assert message.thread_id == nil
    assert message.text == "hello"
    assert message.formatted == "hello"
    assert message.attachments == []
    assert message.is_mention == false
  end

  test "reply transport ID and context do not synthesize each other" do
    assert %{external_reply_to_id: "parent", reply_context: nil} =
             Message.new(%{id: "m1", external_reply_to_id: "parent"})

    assert %{external_reply_to_id: nil, reply_context: %Chat.ReplyContext{id: "quoted"}} =
             Message.new(%{id: "m1", reply_context: %{id: "quoted"}})
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

  test "Author.new/1 preserves stable identity, email, and system state" do
    author =
      Chat.Author.new(%{
        user_id: "provider-1",
        user_name: "casey",
        id: "stable-1",
        email: "casey@example.com",
        is_system: true
      })

    assert author.id == "stable-1"
    assert author.user_id == "provider-1"
    assert author.email == "casey@example.com"
    refute author.is_bot
    assert author.is_system
  end

  test "legacy human Author.new/1 keeps enriched fields unset and defaults false" do
    author = Chat.Author.new(%{user_id: "human-1", user_name: "casey"})
    assert author.id == nil
    assert author.email == nil
    refute author.is_bot
    refute author.is_system
  end

  test "Message.new/1 normalizes content attachments into media structs" do
    message =
      Message.new(%{
        external_room_id: "room_1",
        external_message_id: "m1",
        attachments: [
          Video.new("https://example.com/video.mp4", media_type: "video/mp4", duration: 8),
          File.new("https://example.com/doc.pdf", "doc.pdf", media_type: "application/pdf")
        ]
      })

    assert [
             %Media{kind: :video, media_type: "video/mp4", duration: 8},
             %Media{kind: :file, filename: "doc.pdf", media_type: "application/pdf"}
           ] = message.attachments
  end

  test "markdown helpers provide stringify, plain text, walk, and table fallbacks" do
    markdown =
      Markdown.root([
        Markdown.heading(2, "Overview"),
        Markdown.paragraph([
          Markdown.text("hello "),
          Markdown.strong("world"),
          Markdown.text(" from "),
          Markdown.link("jido", "https://example.com")
        ]),
        Markdown.table([["Name", "Role"], ["Ada", "admin"], ["Bea", "editor"]])
      ])

    walked =
      Markdown.walk(markdown, fn
        %Jido.Chat.Markdown.Node{type: :text, text: "world"} = node -> %{node | text: "team"}
        node -> node
      end)

    assert Markdown.stringify(markdown) =~ "## Overview"
    assert Markdown.plain_text(walked) =~ "hello team from jido"
    assert Markdown.table_to_ascii(markdown) =~ "Name"
    assert Markdown.parse("## Parsed\n\nhello").root.type == :root
  end

  test "typed markdown and card payloads preserve canonical rich content" do
    markdown =
      Markdown.root([Markdown.heading(2, "Status"), Markdown.paragraph("Everything is green.")])

    ast_payload = Postable.ast(markdown) |> Postable.to_payload()
    assert %Markdown{} = ast_payload.ast
    assert ast_payload.text == "Status\n\nEverything is green."
    assert ast_payload.formatted =~ "## Status"

    card =
      Card.new(%{
        title: "Deployment",
        summary: "Ready to ship",
        components: [
          Card.fields([Card.field("Version", "1.2.3"), Card.field("Region", "us-central")]),
          Card.actions([
            Card.button("Approve", "deploy:approve", value: "ship"),
            Card.link_button("Logs", "https://example.com/logs")
          ]),
          Card.table(["Name", "State"], [["api", "ok"], ["worker", "ok"]])
        ]
      })

    card_payload = Postable.card(card) |> Postable.to_payload()
    assert %Card{} = card_payload.card
    assert card_payload.fallback_text =~ "Deployment"
    assert card_payload.fallback_text =~ "Version: 1.2.3"
    assert card_payload.text == card_payload.fallback_text
  end

  test "post payloads normalize outbound attachments into typed structs" do
    payload =
      Postable.new(%{
        kind: :text,
        text: "hello",
        attachments: [
          Image.new("https://example.com/photo.jpg", media_type: "image/jpeg", alt_text: "photo"),
          %{path: "/tmp/report.pdf", media_type: "application/pdf"}
        ]
      })
      |> Postable.to_payload()

    assert [
             %Attachment{
               kind: :image,
               url: "https://example.com/photo.jpg",
               media_type: "image/jpeg",
               metadata: %{alt_text: "photo"}
             },
             %Attachment{
               kind: :file,
               path: "/tmp/report.pdf",
               filename: "report.pdf",
               media_type: "application/pdf"
             }
           ] = payload.attachments
  end

  test "post payloads normalize outbound files into typed structs" do
    payload =
      Postable.new(%{
        markdown: "**hello**",
        files: [
          "/tmp/report.pdf",
          %{url: "https://example.com/photo.jpg", media_type: "image/jpeg"}
        ]
      })
      |> Postable.to_payload()

    assert payload.kind == :markdown

    assert [
             %FileUpload{kind: :file, path: "/tmp/report.pdf", filename: "report.pdf"},
             %FileUpload{
               kind: :image,
               url: "https://example.com/photo.jpg",
               media_type: "image/jpeg"
             }
           ] = payload.files

    assert [
             %Attachment{filename: "report.pdf", kind: :file},
             %Attachment{kind: :image, url: "https://example.com/photo.jpg"}
           ] = PostPayload.outbound_attachments(payload)
  end

  test "stream postables preserve text chunks and normalize structured chunks" do
    payload =
      Postable.stream([
        "hello",
        %{kind: :status, text: "working", metadata: %{phase: 1}},
        %{kind: :step_start, payload: %{label: "Draft response"}},
        StreamChunk.text("done")
      ])
      |> Postable.to_payload()

    assert payload.kind == :stream
    assert payload.stream |> Enum.at(0) == "hello"
    assert %StreamChunk{kind: :status, text: "working"} = Enum.at(payload.stream, 1)
    assert %StreamChunk{kind: :step_start} = Enum.at(payload.stream, 2)
    assert %StreamChunk{kind: :text, text: "done"} = Enum.at(payload.stream, 3)
    assert payload.fallback_text == "hello\n> **Status:** working\n\n- [ ] Draft response\ndone"
  end

  test "schema constructor errors raise Splode validation errors" do
    assert_raise Jido.Chat.Errors.Validation, fn -> Participant.new(%{}) end
  end

  test "Text.new/1" do
    text = Text.new("hello")
    assert text.type == :text
    assert text.text == "hello"
  end

  test "Image.new/2 and from_base64/3" do
    image = Image.new("https://example.com/photo.jpg", media_type: "image/jpeg", alt_text: "photo")
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

  test "Media.normalize/1 preserves typed attachment details" do
    image = Media.normalize(Image.from_base64("base64==", "image/png", alt_text: "inline"))
    audio = Media.normalize(Audio.new("https://example.com/audio.mp3", duration: 12))
    video = Media.normalize(%{type: :video, url: "https://example.com/video.mp4", duration: 8})
    file = Media.normalize("/tmp/report.pdf")
    assert image.kind == :image
    assert image.media_type == "image/png"
    assert image.metadata.alt_text == "inline"
    assert audio.kind == :audio
    assert audio.duration == 12
    assert video.kind == :video
    assert video.duration == 8
    assert file.kind == :file
    assert file.filename == "report.pdf"
    assert file.metadata.path == "/tmp/report.pdf"
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
