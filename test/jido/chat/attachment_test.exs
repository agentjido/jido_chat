defmodule Jido.Chat.AttachmentTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{Attachment, FileUpload, Media}
  alias Jido.Chat.Content.{Audio, File, Image, Video}

  test "content blocks retain bytes and descriptive metadata across media and upload conversion" do
    inputs = [
      Image.from_base64("aW1hZ2U=", "image/png", alt_text: "Diagram", width: 20, height: 10),
      Audio.from_base64("YXVkaW8=", "audio/mp3", duration: 4, transcript: "Hello"),
      Video.from_base64("dmlkZW8=", "video/mp4",
        duration: 5,
        width: 40,
        height: 30,
        thumbnail_url: "https://example.test/preview.png"
      ),
      File.from_base64("ZmlsZQ==", "notes.txt", "text/plain", size: 4)
    ]

    for input <- inputs do
      attachment = Attachment.normalize(input)
      media = Media.normalize(input)
      upload = FileUpload.normalize(input)
      assert attachment.data == input.data
      assert Attachment.normalize(media) == attachment
      assert Attachment.normalize(upload) == attachment
      assert FileUpload.normalize(attachment) == upload
      assert FileUpload.to_map(FileUpload.from_map(FileUpload.to_map(upload))) == FileUpload.to_map(upload)
    end

    [image, audio, video, file] = Attachment.normalize_many(inputs)
    assert {image.kind, image.width, image.height, image.metadata} == {:image, 20, 10, %{alt_text: "Diagram"}}

    assert {audio.kind, audio.duration, audio.media_type, audio.metadata} ==
             {:audio, 4, "audio/mp3", %{transcript: "Hello"}}

    assert {video.kind, video.duration, video.metadata} ==
             {:video, 5, %{thumbnail_url: "https://example.test/preview.png"}}

    assert {file.kind, file.filename, file.size_bytes} == {:file, "notes.txt", 4}
  end

  test "URL content blocks retain remote references without invented data or metadata" do
    inputs = [
      Audio.new("https://example.test/a.ogg", media_type: "audio/ogg"),
      Video.new("https://example.test/v.mp4", media_type: "video/mp4"),
      File.new("https://example.test/f.pdf", "f.pdf", media_type: "application/pdf")
    ]

    assert Enum.map(Media.normalize_many(inputs), & &1.kind) == [:audio, :video, :file]

    for input <- inputs do
      attachment = Attachment.normalize(input)
      assert attachment.url == input.url
      assert attachment.data == nil
      assert attachment.metadata == %{}
      assert Attachment.new(attachment) == attachment
      assert Media.new(Media.normalize(input)) == Media.normalize(input)
      assert Media.normalize(Media.normalize(input)) == Media.normalize(input)
    end
  end

  test "remote and local references infer kind and filename without inventing a MIME type" do
    for {reference, kind, filename} <- [
          {"https://example.test/image.PNG?download=1", :image, "image.PNG"},
          {"/tmp/audio.mp3", :audio, "audio.mp3"},
          {"https://example.test", :file, nil},
          {"https://example.test/", :file, nil},
          {".", :file, nil},
          {"", :file, nil}
        ] do
      attachment = Attachment.normalize(reference)
      media = Media.normalize(reference)
      assert {attachment.kind, attachment.filename, attachment.media_type} == {kind, filename, nil}
      assert {media.kind, media.filename, media.media_type} == {kind, filename, nil}
      assert Attachment.normalize(media) == attachment
    end

    assert Attachment.normalize("/tmp/audio.mp3").path == "/tmp/audio.mp3"
    assert Attachment.normalize("https://example.test/image.png").path == nil
    assert Media.normalize("/tmp/audio.mp3").metadata == %{path: "/tmp/audio.mp3"}
  end

  test "legacy maps retain metadata and accept only known explicit kinds" do
    for {kind, expected} <- [
          {"image", :image},
          {"audio", :audio},
          {"video", :video},
          {"file", :file},
          {"unknown", :image},
          {123, :image}
        ] do
      attrs = %{
        "type" => kind,
        "name" => "picture.png",
        "mime_type" => " IMAGE/PNG ",
        "size" => 5,
        "alt_text" => "Description",
        "transcript" => "Words",
        "thumbnail_url" => "preview",
        "metadata" => %{source: "fixture"}
      }

      attachment = Attachment.normalize(attrs)
      media = Media.normalize(attrs)

      assert {attachment.kind, attachment.filename, attachment.media_type, attachment.size_bytes} ==
               {expected, "picture.png", "image/png", 5}

      assert media.kind == expected

      assert attachment.metadata ==
               %{source: "fixture", alt_text: "Description", transcript: "Words", thumbnail_url: "preview"}

      assert media.metadata == attachment.metadata
    end

    media = Media.new(%{kind: :file, metadata: %{"path" => "/tmp/file", "data" => "bytes", "keep" => true}})
    attachment = Attachment.normalize(media)
    assert {attachment.path, attachment.data, attachment.metadata} == {"/tmp/file", "bytes", %{"keep" => true}}
    assert Attachment.new(%{filename: " ", url: "https://example.test/x.mp4"}).kind == :video
    assert FileUpload.new(%{type: :audio, data: "bytes"}).kind == :audio
    upload = FileUpload.new(%{kind: :file, data: "bytes"})
    assert FileUpload.normalize_many([upload]) == [upload]
    assert FileUpload.new(upload) == upload
  end
end
