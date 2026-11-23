defmodule Jido.Chat.Discord.LiveFiles do
  @moduledoc false
  import ExUnit.Assertions
  import Jido.Chat.LiveCase, only: [on_cleanup: 1]
  alias Jido.Chat
  alias Jido.Chat.Discord.LiveHelpers, as: L
  alias Jido.Chat.LiveCase.Probes

  @photo Path.expand("../../fixtures/photo.png.b64", __DIR__)
  @video Path.expand("../../../jido_chat/providers/telegram/fixtures/square-video.mp4.b64", __DIR__)

  def inline(ctx) do
    bytes = <<0, 255, 1, 2, 10, 13, 65>>
    filename = "jido-live-#{ctx.run_id}.bin"
    sent = send_file(ctx, inline_source(bytes, filename), [], :public)
    assert %{"name" => ^filename, "resource_ref" => ref} = attachment(ctx, sent)
    assert download(ctx, ref, :public) == bytes
  end

  def text_and_file(ctx) do
    Probes.send_text(ctx)
    inline(ctx)
  end

  def reuse(ctx) do
    bytes = "Jido live #{ctx.run_id}: local source"
    {path, source} = local_source(ctx, bytes)
    filename = Path.basename(path)
    original = send_file(ctx, source, [], :public)
    assert %{"name" => ^filename, "resource_ref" => original_ref} = attachment(ctx, original)
    assert download(ctx, original_ref, :public) == bytes

    copy = send_file(ctx, original_ref, [], :public)
    assert %{"name" => ^filename, "resource_ref" => copy_ref} = attachment(ctx, copy)
    assert copy_ref != original_ref
    assert download(ctx, copy_ref, :public) == bytes
  end

  def image(ctx) do
    bytes = fixture(@photo)
    sent = send_file(ctx, inline_source(bytes, "jido-live.png"), [media_kind: :image], :public)
    media = normalized_media(ctx, sent)
    assert %{"kind" => "image", "width" => 64, "height" => 64} = media
    assert download(ctx, media["resource_ref"], :public) == bytes
  end

  def native_document(ctx) do
    payload = %{"sdk" => "jido", "run" => ctx.run_id}
    bytes = Jason.encode!(payload)
    sent = send_file(ctx, inline_source(bytes, "jido-live.json"), [], :native)
    assert %{"name" => "jido-live.json", "resource_ref" => ref} = attachment(ctx, sent)
    returned = download(ctx, ref, :native)
    assert bytes == returned
    assert Jason.decode!(returned) == payload
  end

  def native_media(ctx) do
    for {path, filename, kind, dimension} <- [
          {@photo, "jido-live.png", "image", 64},
          {@video, "jido-live.mp4", "video", 240}
        ] do
      bytes = fixture(path)
      sent = send_file(ctx, inline_source(bytes, filename), [], :native)

      assert %{"kind" => ^kind, "name" => ^filename, "width" => ^dimension, "height" => ^dimension} =
               media = normalized_media(ctx, sent)

      assert byte_size(download(ctx, media["resource_ref"], :native)) > 0
    end
  end

  def native_local(ctx) do
    bytes = "Jido live #{ctx.run_id}: native local source"
    {path, source} = local_source(ctx, bytes)
    sent = send_file(ctx, source, [], :native)
    filename = Path.basename(path)
    assert %{"name" => ^filename, "resource_ref" => ref} = attachment(ctx, sent)
    assert download(ctx, ref, :native) == File.read!(path)
  end

  defp local_source(ctx, bytes) do
    path = Path.join(System.tmp_dir!(), "jido-discord-live-#{ctx.run_id}.txt")
    File.write!(path, bytes, [:exclusive])
    on_cleanup(fn -> File.rm!(path) end)
    {path, %{"client_id" => ctx.client.id, "kind" => "file", "id" => path}}
  end

  defp send_file(ctx, source, opts, mode) do
    c = ctx.client
    room = ctx.room_id
    caption = "Jido live #{ctx.run_id}: attachment"

    sent =
      case mode do
        :public -> Chat.send_file(c, room, source, [caption: caption] ++ opts) |> L.complete(c)
        :native -> L.native(c, Chat.SendFile, %{"room_id" => room, "source" => source, "caption" => caption})
      end

    L.track_message(c, room, sent)
    assert sent["room_id"] == room
    assert sent["text"] == caption
    sent
  end

  defp attachment(ctx, sent) do
    raw = L.raw_message(ctx.client, ctx.room_id, sent["id"])
    attachment(ctx, sent, raw)
  end

  defp attachment(ctx, sent, raw) do
    assert [media] = sent["media"]
    assert [attachment] = raw["attachments"]
    assert attachment["filename"] == media["name"]

    assert media["resource_ref"] == %{
             "client_id" => ctx.client.id,
             "kind" => "media",
             "id" => "discord://attachment/#{ctx.room_id}/#{sent["id"]}/#{attachment["id"]}"
           }

    media
  end

  defp normalized_media(ctx, sent) do
    raw = L.raw_message(ctx.client, ctx.room_id, sent["id"])

    assert {:ok, %{signals: [fact]}} =
             Chat.normalize(ctx.client, {"MESSAGE_CREATE", Map.put(raw, "guild_id", ctx.guild)})

    assert fact.type == Chat.Signal.MessageReceived.type()
    assert fact.data["message_id"] == sent["id"]
    assert fact.data["room_id"] == ctx.room_id
    assert fact.data["text"] == sent["text"]
    assert [media] = fact.data["media"]
    assert media == attachment(ctx, sent, raw)
    assert :ok = Chat.AdapterTestKit.Assertions.assert_json_round_trip(fact, Chat.catalog(ctx.client))
    media
  end

  defp download(ctx, ref, :public), do: Chat.download_file(ctx.client, ref) |> L.complete(ctx.client) |> bytes()
  defp download(ctx, ref, :native), do: L.native(ctx.client, Chat.DownloadFile, %{"resource_ref" => ref}) |> bytes()
  defp bytes(result), do: Base.decode64!(result["content_base64"])
  defp fixture(path), do: path |> File.read!() |> Base.decode64!(ignore: :whitespace)
  defp inline_source(bytes, name), do: %{"content_base64" => Base.encode64(bytes), "filename" => name}
end
