defmodule Jido.Chat.PortableValuesTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{Actor, AI, Content, FileSource, Media, Message, Post, ResourceRef}

  test "actor and resource values accept wire maps and round trip" do
    actor =
      Actor.new(%{
        "id" => "user-1",
        "display_name" => "Ada",
        "is_bot" => true
      })

    assert actor.kind == :bot
    assert actor.display_name == "Ada"
    assert Actor.from_map(Actor.to_map(actor)) == actor

    reference = ResourceRef.new(%{"id" => "file-1", "client_id" => "support", "kind" => "file"})
    assert ResourceRef.from_map(ResourceRef.to_map(reference)) == reference
  end

  test "file sources require exactly one portable source" do
    reference = ResourceRef.new(%{id: "file-1", client_id: "support", kind: :file})
    source = FileSource.reference(reference, filename: "report.txt")

    assert FileSource.from_map(FileSource.to_map(source)) == source

    assert_raise Jido.Chat.Errors.Validation, fn ->
      FileSource.new(%{kind: :url, url: "https://example.test/file", content_base64: "YQ=="})
    end
  end

  test "posts preserve rich content through portable maps" do
    reference = ResourceRef.new(%{id: "image-1", client_id: "support", kind: :media})

    media =
      Media.new(%{
        kind: :image,
        source: FileSource.reference(reference),
        alt_text: "Status chart"
      })

    post =
      Post.new(%{
        content: [
          Content.text("Ready"),
          Content.markdown("**Ship it**"),
          Content.media(media)
        ],
        mentions: ["operator"],
        reply_to_id: "message-1"
      })

    assert Post.from_map(Post.to_map(post)) == post
    assert Post.fallback_text(post) == "Ready\n**Ship it**\nStatus chart"
  end

  test "messages convert to portable AI history" do
    message =
      Message.new(%{
        id: "message-2",
        room_id: "room-1",
        actor: Actor.new(%{id: "assistant", kind: :agent}),
        role: :assistant,
        content: [Content.text("Done")]
      })

    assert Message.from_map(Message.to_map(message)) == message
    assert AI.to_messages([message]) == [%{"role" => "assistant", "content" => "Done"}]
  end
end
