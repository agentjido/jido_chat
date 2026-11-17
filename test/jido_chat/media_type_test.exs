defmodule Jido.Chat.MediaTypeTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.MediaType

  test "normalizes valid provider MIME values and rejects invalid values" do
    assert MediaType.normalize(" Image/PNG; charset=binary ") == "image/png"
    assert MediaType.normalize("") == nil
    assert MediaType.normalize("png") == nil
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

  test "recognizes the supported common file signatures" do
    signatures = [
      {<<"GIF87a", 0>>, "image/gif"},
      {<<"GIF89a", 0>>, "image/gif"},
      {<<"RIFF", 0, 0, 0, 0, "WEBP", 0>>, "image/webp"},
      {<<"BM", 0>>, "image/bmp"},
      {<<"%PDF-1.7">>, "application/pdf"},
      {<<0x1F, 0x8B, 0>>, "application/gzip"},
      {<<"PK", 3, 4, 0>>, "application/zip"},
      {<<"PK", 5, 6, 0>>, "application/zip"},
      {<<"PK", 7, 8, 0>>, "application/zip"}
    ]

    Enum.each(signatures, fn {data, media_type} ->
      assert MediaType.sniff(data) == media_type
    end)
  end

  test "classifies canonical media kinds and defaults unknown values to files" do
    assert MediaType.kind("image/png") == :image
    assert MediaType.kind(nil, "voice.ogg") == :audio
    assert MediaType.kind("video/mp4") == :video
    assert MediaType.kind("application/pdf") == :file
    assert MediaType.kind(nil, "README") == :file
    assert MediaType.from_filename(123) == nil
    assert MediaType.from_filename("http://") == nil
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
end
