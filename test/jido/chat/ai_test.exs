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

  test "system author role takes precedence below explicit role and above is_me" do
    system_author =
      Message.new(%{
        id: "system",
        text: "system message",
        author: Author.new(%{user_id: "system", user_name: "policy", is_system: true, is_me: true})
      })

    explicit_user =
      Message.new(%{
        id: "explicit",
        text: "explicit user",
        metadata: %{role: :user},
        author: Author.new(%{user_id: "system", user_name: "policy", is_system: true})
      })

    explicit_assistant =
      Message.new(%{
        id: "explicit-assistant",
        text: "explicit assistant",
        metadata: %{role: :assistant},
        author: Author.new(%{user_id: "system", user_name: "policy", is_system: true})
      })

    assert [%{role: "system"}, %{role: "user"}, %{role: "assistant"}] =
             AI.to_messages([system_author, explicit_user, explicit_assistant])
  end

  test "ISO timestamps sort by time across fractional seconds and offsets" do
    messages = [
      %{id: "fraction", text: "fraction", created_at: "2026-01-01T00:00:00.500000Z"},
      %{id: "whole", text: "whole", created_at: "2026-01-01T00:00:00Z"},
      %{id: "offset", text: "offset", created_at: "2026-01-01T01:00:00.250000+01:00"}
    ]

    assert Enum.map(AI.to_messages(messages), & &1.content) == ["whole", "offset", "fraction"]
  end

  test "mixed date representations share the documented microsecond scale" do
    messages = [
      %{id: "iso", text: "iso", created_at: "2026-01-01T00:00:03Z"},
      %{id: "naive", text: "naive", created_at: ~N[2026-01-01 00:00:02]},
      %{id: "integer", text: "integer", created_at: DateTime.to_unix(~U[2026-01-01 00:00:01Z], :microsecond)},
      %{id: "datetime", text: "datetime", created_at: ~U[2026-01-01 00:00:00Z]},
      %{id: "naive-iso", text: "naive-iso", created_at: "2026-01-01T00:00:02.500000"}
    ]

    assert Enum.map(AI.to_messages(messages), & &1.content) == ["datetime", "integer", "naive", "naive-iso", "iso"]
  end

  test "equal times keep input order across date representations" do
    messages = [
      %{id: "iso", text: "iso", created_at: "2026-01-01T00:00:00.000000Z"},
      %{id: "naive", text: "naive", created_at: ~N[2026-01-01 00:00:00]},
      %{id: "integer", text: "integer", created_at: DateTime.to_unix(~U[2026-01-01 00:00:00Z], :microsecond)},
      %{id: "datetime", text: "datetime", created_at: ~U[2026-01-01 00:00:00Z]}
    ]

    assert Enum.map(AI.to_messages(messages), & &1.content) == ["iso", "naive", "integer", "datetime"]
  end

  test "integer timestamps keep their given scale and invalid timestamps keep their legacy order" do
    messages = [
      %{id: "invalid-z", text: "invalid-z", created_at: "z-invalid"},
      %{id: "positive", text: "positive", created_at: 2},
      %{id: "missing", text: "missing"},
      %{id: "unsupported", text: "unsupported", created_at: %{provider: "unknown"}},
      %{id: "invalid-a", text: "invalid-a", created_at: "a-invalid"},
      %{id: "negative", text: "negative", created_at: -1}
    ]

    assert Enum.map(AI.to_messages(messages), & &1.content) ==
             ["negative", "positive", "missing", "unsupported", "invalid-a", "invalid-z"]
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

  test "empty and formatted messages use safe content and full-name fallbacks" do
    messages = [
      %{id: "empty"},
      %{id: "formatted", formatted: "Formatted", author: %Author{user_id: "ada", user_name: nil, full_name: "Ada"}}
    ]

    assert AI.to_messages(messages, %{"include_names" => true, "transform" => &Map.put(&1, :source, "fixture")}) ==
             [
               %{role: "user", content: "", source: "fixture"},
               %{role: "user", content: "Formatted", name: "Ada", source: "fixture"}
             ]

    assert AI.to_messages([%{id: "empty", text: ""}], :invalid) == [%{role: "user", content: ""}]
  end

  test "unsupported attachment hooks can skip or return one or more content parts" do
    message = %{id: "audio", attachments: [%{kind: :audio}]}

    for response <- [nil, :skip, 42] do
      assert AI.to_messages([message], unsupported_attachment: fn _, _ -> response end) ==
               [%{role: "user", content: ""}]
    end

    part = %{type: "audio", data: "bytes"}

    for response <- [part, [part]] do
      assert AI.to_messages([message], unsupported_attachment: fn _, _ -> response end) ==
               [%{role: "user", content: [part]}]
    end

    assert AI.to_messages([message], unsupported_attachment: :invalid) == [%{role: "user", content: ""}]
    assert AI.to_messages([message]) == [%{role: "user", content: ""}]

    assert AI.to_messages([%{id: "file", attachments: [%{filename: "binary.bin"}]}]) ==
             [%{role: "user", content: ""}]
  end

  test "text-like attachment fetching handles failed fetches and string metadata" do
    message = %{id: "xml", attachments: [%{filename: "data.bin", media_type: "application/xml"}]}
    assert [%{content: "<data/>"}] = AI.to_messages([message], fetch_attachment: fn _ -> "<data/>" end)

    for fetch <- [nil, :invalid, fn _ -> {:error, :unavailable} end] do
      assert [%{content: ""}] = AI.to_messages([message], fetch_attachment: fetch)
    end

    assert [%{content: "stored"}] =
             AI.to_messages([%{id: "text", attachments: [%{filename: "notes.md", metadata: %{"data" => "stored"}}]}])

    assert [%{content: "fetched"}] =
             AI.to_messages([%{id: "text", attachments: [%{filename: "notes.csv"}]}],
               fetch_attachment: fn _ -> {:ok, "fetched"} end
             )
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
