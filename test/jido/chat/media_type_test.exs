defmodule Jido.Chat.MediaTypeTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{AI, Attachment, FileUpload, Media, MediaType, Message}

  test "normalizes valid provider MIME values and rejects invalid values" do
    assert MediaType.normalize(" Image/PNG; charset=binary ") == "image/png"
    assert MediaType.normalize("") == nil
    assert MediaType.normalize("png") == nil

    assert %Media{kind: :image, media_type: "image/png"} =
             Media.new(%{media_type: " Image/PNG; charset=binary "})

    assert %Media{kind: :image, media_type: nil} =
             Media.new(%{media_type: "not-a-mime", filename: "photo.png"})
  end

  test "uses only caller-supplied provider defaults" do
    assert MediaType.resolve(nil) == nil
    assert MediaType.resolve(nil, provider_default: "image/jpeg") == "image/jpeg"
    assert MediaType.resolve("image/png", provider_default: "image/jpeg") == "image/png"
  end

  test "uses a valid download response media type before byte and filename hints" do
    png = <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, "payload">>

    assert MediaType.resolve(nil,
             response_media_type: " Image/WebP; charset=binary ",
             data: png,
             filename: "photo.jpg"
           ) == "image/webp"

    assert MediaType.resolve(nil,
             provider_default: "image/jpeg",
             response_media_type: "image/webp"
           ) == "image/jpeg"
  end

  test "prefers downloaded byte signatures over filename hints" do
    png = <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, "payload">>

    assert MediaType.resolve(nil, data: png, filename: "misleading.jpg") == "image/png"
    assert MediaType.sniff(<<0xFF, 0xD8, 0xFF, "jpeg">>) == "image/jpeg"
    assert MediaType.sniff("unknown") == nil
  end

  test "uses filename and URL extensions only as last-choice hints" do
    assert MediaType.from_filename("photo.JPEG") == "image/jpeg"

    assert MediaType.from_filename("https://example.test/files/photo.png?token=secret") ==
             "image/png"

    assert MediaType.from_filename("https://example.test/download") == nil

    assert MediaType.resolve(nil,
             filename: " ",
             url: "https://example.test/files/photo.PNG?token=secret"
           ) == "image/png"

    assert MediaType.resolve(nil, filename: 123, path: "/tmp/audio.ogg") == "audio/ogg"
  end

  test "infers media kind without inventing media_type" do
    media = Media.new(%{filename: "photo.png"})
    attachment = Attachment.new(%{url: "https://example.test/audio.ogg"})
    misleading = Media.new(%{media_type: "application/pdf", filename: "photo.png"})

    assert media.kind == :image
    assert media.media_type == nil
    assert attachment.kind == :audio
    assert attachment.media_type == nil
    assert misleading.kind == :file
    assert misleading.media_type == "application/pdf"
  end

  test "media maps merge attachment details with existing atom or string metadata" do
    for attrs <- [
          %{
            data: "file body",
            alt_text: "File",
            transcript: "Spoken",
            thumbnail_url: "https://example.test/thumb.png",
            path: "/tmp/file.txt"
          },
          %{
            "data" => "file body",
            "alt_text" => "File",
            "transcript" => "Spoken",
            "thumbnail_url" => "https://example.test/thumb.png",
            "path" => "/tmp/file.txt"
          }
        ],
        metadata <- [%{}, %{provider: "fixture"}] do
      key = if Map.has_key?(attrs, :data), do: :metadata, else: "metadata"
      media = attrs |> Map.put(key, metadata) |> Media.new()

      assert media.metadata ==
               Map.merge(metadata, %{
                 data: "file body",
                 alt_text: "File",
                 transcript: "Spoken",
                 thumbnail_url: "https://example.test/thumb.png",
                 path: "/tmp/file.txt"
               })
    end
  end

  test "nested media maps retain file text for AI conversion when metadata is present" do
    for message_attrs <- [
          %{
            id: "one",
            attachments: [
              %{filename: "notes.txt", media_type: "text/plain", data: "note body", metadata: %{provider: "fixture"}}
            ]
          },
          %{
            "id" => "one",
            "attachments" => [
              %{
                "filename" => "notes.txt",
                "media_type" => "text/plain",
                "data" => "note body",
                "metadata" => %{"provider" => "fixture"}
              }
            ]
          }
        ] do
      message = Message.new(message_attrs)
      assert [%Media{metadata: metadata}] = message.attachments
      assert metadata[:data] == "note body"
      assert [%{role: "user", content: "note body"}] = AI.to_messages([message])
    end
  end

  test "media maps keep file bytes and paths when converted to outbound upload values" do
    for attrs <- [
          %{data: "file body", path: "/tmp/file.txt", metadata: %{provider: "fixture"}},
          %{"data" => "file body", "path" => "/tmp/file.txt", "metadata" => %{"provider" => "fixture"}}
        ] do
      media = Media.normalize(attrs)
      assert %Attachment{data: "file body", path: "/tmp/file.txt"} = Attachment.normalize(media)
      assert %FileUpload{data: "file body", path: "/tmp/file.txt"} = FileUpload.normalize(media)
    end
  end
end
