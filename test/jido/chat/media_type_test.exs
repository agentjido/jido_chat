defmodule Jido.Chat.MediaTypeTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{Attachment, Media, MediaType}

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
end
