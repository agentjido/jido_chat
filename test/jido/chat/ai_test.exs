defmodule Jido.Chat.AITest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{AI, Author, Message}

  test "to_messages sorts chronologically, maps roles, and includes names" do
    assistant =
      Message.new(%{
        id: "m2",
        text: "I can help",
        created_at: ~U[2026-04-12 22:00:01Z],
        author: Author.new(%{user_id: "bot", user_name: "jido", is_me: true})
      })

    user =
      Message.new(%{
        id: "m1",
        text: "hello",
        created_at: ~U[2026-04-12 22:00:00Z],
        author: Author.new(%{user_id: "user", user_name: "casey"})
      })

    system =
      Message.new(%{
        id: "m0",
        text: "policy",
        created_at: ~U[2026-04-12 21:59:59Z],
        metadata: %{role: :system}
      })

    assert [
             %{role: "system", content: "policy"},
             %{role: "user", content: "hello", name: "casey"},
             %{role: "assistant", content: "I can help", name: "jido"}
           ] = AI.to_messages([assistant, user, system], include_names: true)
  end

  test "to_messages emits multipart content for images and text-like files" do
    message =
      Message.new(%{
        id: "m1",
        text: "review these",
        attachments: [
          %{type: :image, url: "https://example.com/photo.png", media_type: "image/png"},
          %{
            type: :file,
            filename: "notes.txt",
            media_type: "text/plain",
            metadata: %{data: "note body"}
          }
        ]
      })

    assert [
             %{
               role: "user",
               content: [
                 %{type: "text", text: "review these"},
                 %{
                   type: "image",
                   url: "https://example.com/photo.png",
                   media_type: "image/png",
                   metadata: %{}
                 },
                 %{type: "text", text: "note body", filename: "notes.txt"}
               ]
             }
           ] = AI.to_messages([message])
  end

  test "to_messages can fetch text attachments and handle unsupported media with hooks" do
    message =
      Message.new(%{
        id: "m1",
        text: "context",
        attachments: [
          %{type: :file, filename: "schema.json", media_type: "application/json"},
          %{type: :audio, url: "https://example.com/audio.mp3", media_type: "audio/mpeg"}
        ]
      })

    [ai_message] =
      AI.to_messages([message],
        fetch_attachment: fn
          %{filename: "schema.json"} -> {:ok, "{\"ok\":true}"}
          _ -> nil
        end,
        unsupported_attachment: fn attachment, _message ->
          "unsupported:#{attachment.kind}"
        end,
        transform: fn ai_message, _message -> Map.put(ai_message, :metadata, %{source: :test}) end
      )

    assert ai_message.role == "user"
    assert ai_message.metadata == %{source: :test}
    assert %{type: "text", text: "{\"ok\":true}", filename: "schema.json"} in ai_message.content
    assert %{type: "text", text: "unsupported:audio"} in ai_message.content
  end

  test "to_ai_messages accepts Chat SDK-style camelCase option aliases" do
    message =
      Message.new(%{
        id: "m1",
        text: "hello",
        attachments: [
          %{type: :file, filename: "schema.json", media_type: "application/json"},
          %{type: :audio, url: "https://example.com/audio.mp3", media_type: "audio/mpeg"}
        ],
        author: Author.new(%{user_id: "user", user_name: "casey"})
      })

    [ai_message] =
      AI.to_ai_messages([message],
        includeNames: true,
        fetchAttachment: fn %{filename: "schema.json"} -> "{\"ok\":true}" end,
        onUnsupportedAttachment: fn attachment, _message -> "unsupported:#{attachment.kind}" end,
        transformMessage: fn ai_message, _message -> Map.put(ai_message, :source, :camel_case) end
      )

    assert ai_message.name == "casey"
    assert ai_message.source == :camel_case
    assert %{type: "text", text: "{\"ok\":true}", filename: "schema.json"} in ai_message.content
    assert %{type: "text", text: "unsupported:audio"} in ai_message.content
  end
end
