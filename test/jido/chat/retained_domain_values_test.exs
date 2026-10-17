defmodule Jido.Chat.RetainedDomainValuesTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{
    Attachment,
    Author,
    Card,
    ChannelRef,
    FileUpload,
    Markdown,
    Media,
    Message,
    Modal,
    Participant,
    PostPayload,
    Postable,
    ReplyContext,
    Room,
    Thread,
    UserInfo,
    MessageSubject
  }

  alias Jido.Chat.Content.{Audio, File, Image, Text, ToolResult, ToolUse, Video}

  test "domain message/reply records keep independent external identity and content" do
    record =
      Message.new(%{
        external_room_id: "room-1",
        external_message_id: "message-1",
        text: "hello",
        external_reply_to_id: "transport-parent",
        reply_context: %{id: "quoted-parent", text: "quoted text"}
      })

    assert record.id == "message-1"
    assert record.external_reply_to_id == "transport-parent"
    assert record.reply_context.id == "quoted-parent"
    assert record.text == "hello"
    assert record.formatted == "hello"
    assert record.attachments == []
    assert record.thread_id == nil
    assert record.reply_context.text == "quoted text"
  end

  test "retained identity, author, and input constructors preserve their values" do
    assert Room.new(%{type: :direct}).type == :direct
    assert Participant.new(%{type: :human}).type == :human

    author =
      Author.new(%{
        "user_id" => "transport",
        "user_name" => "Tester",
        "id" => "stable",
        "email" => "test@example.com",
        "is_bot" => true
      })

    assert author.id == "stable"
    assert author.user_id == "transport"
    assert author.email == "test@example.com"
    assert author.is_bot
    reply = ReplyContext.new(%{id: "quote", text: "quoted", nested_reply: %{id: "ignored"}})
    assert reply.id == "quote"
    refute Map.has_key?(Map.from_struct(reply), :nested_reply)
    assert FileUpload.new(%{data: "private", filename: "file.txt"}).filename == "file.txt"
    assert Attachment.normalize("/tmp/file.txt").path == "/tmp/file.txt"
    assert UserInfo.new(%{id: "user-1", display_name: "User"}).id == "user-1"
    assert MessageSubject.new(%{id: "issue-1", type: "issue"}).id == "issue-1"
  end

  test "thread and channel records are pure references without transport aliases" do
    thread = Thread.new(%{id: "thread-1", adapter_name: :test, adapter: __MODULE__, external_room_id: "room-1"})

    channel =
      ChannelRef.new(%{
        id: "channel-1",
        adapter_name: :test,
        adapter: __MODULE__,
        external_id: "room-1",
        metadata: %{"name" => "Old"}
      })

    assert Thread.channel_id(thread) == "room-1"
    assert Thread.from_map(Thread.to_map(thread)) == thread
    assert ChannelRef.from_map(ChannelRef.to_map(channel)) == channel
    renamed = %{channel | metadata: %{name: "New"}}
    assert ChannelRef.name(renamed) == "New"
    assert renamed.id == channel.id

    for {module, operations} <- [
          {Thread, [:post, :send_file, :edit, :open_modal, :start_typing, :post_ephemeral, :messages]},
          {ChannelRef, [:post, :send_file, :open_modal, :open_thread, :messages, :threads]}
        ] do
      exported = module.__info__(:functions)
      refute Enum.any?(exported, fn {name, _} -> name in operations end)
    end
  end

  test "rich input builders and private streams preserve intent without raw provider payloads" do
    markdown = Postable.markdown("**bold**") |> Postable.to_payload()
    assert markdown.kind == :markdown
    assert markdown.text == "**bold**"
    card = Card.new(%{title: "Title", components: [Card.text("Body")]})
    assert Postable.card(card) |> Postable.to_payload() |> Map.fetch!(:card) == card
    assert Jido.Chat.Adapter.render_card(card) == Card.to_adapter_payload(card)
    modal = Modal.new(%{title: "Title", elements: [Modal.text_input("field", "Label")]})
    assert Jido.Chat.Adapter.render_modal(modal) == Modal.to_adapter_payload(modal)
    stream = Stream.map(["one", "two"], & &1)
    assert Postable.stream(stream) |> Postable.to_payload() |> Map.fetch!(:stream) == stream
    assert_raise Jido.Chat.Errors.Validation, fn -> PostPayload.new(%{kind: :raw, raw: %{provider: true}}) end
    refute function_exported?(Postable, :raw, 1)
  end

  test "content blocks remain separate input/domain values" do
    assert Text.new("hello").text == "hello"
    assert Image.new("https://example.com/image.png").url == "https://example.com/image.png"
    assert Audio.new("https://example.com/audio.wav").url == "https://example.com/audio.wav"
    assert Video.new("https://example.com/video.mp4").url == "https://example.com/video.mp4"
    assert File.new("https://example.com/file.txt", "file.txt", media_type: "text/plain").filename == "file.txt"
    assert ToolUse.new("tool-1", "echo", %{text: "hello"}).name == "echo"
    assert ToolResult.new("tool-1", "done").content == "done"
    assert Media.normalize(%{kind: :image, url: "https://example.com/image.png"}).kind == :image
    assert Markdown.stringify(Markdown.new("**bold**")) == "**bold**"
  end
end
