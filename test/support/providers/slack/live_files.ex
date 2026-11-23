defmodule Jido.Chat.Slack.LiveFiles do
  @moduledoc false
  import ExUnit.Assertions
  alias Jido.Chat
  alias Jido.Chat.LiveCase
  alias Jido.Chat.Signal
  alias Jido.Chat.Slack.{LiveAPI, LiveFixture}

  @photo Path.expand("../../fixtures/photo.png.b64", __DIR__)
  @video Path.expand("../../../jido_chat/providers/telegram/fixtures/square-video.mp4.b64", __DIR__)
  @file_info_attempts 20

  def file(ctx) do
    bytes = fixture_bytes(@photo)
    {metadata, _} = upload(ctx, bytes, "jido-live-#{ctx.run_id}.png", :public)
    assert download(ctx, reference(ctx, metadata), :public) == bytes
  end

  def text_and_file(ctx) do
    LiveCase.Probes.send_text(ctx)
    file(ctx)
  end

  def image(ctx), do: media(ctx, @photo, "png", "image", :public)

  def native_media(ctx) do
    media(ctx, @photo, "png", "image", :native)
    media(ctx, @video, "mp4", "video", :native)
  end

  def document(ctx) do
    document = %{"suite" => "jido-chat", "run" => ctx.run_id}
    bytes = Jason.encode!(document)
    {metadata, _} = upload(ctx, bytes, "jido-live-#{ctx.run_id}.json", :native)
    returned = download(ctx, reference(ctx, metadata), :native)
    assert returned == bytes
    assert Jason.decode!(returned) == document
  end

  defp media(ctx, fixture, extension, kind, mode) do
    bytes = fixture_bytes(fixture)
    name = "jido-live-#{kind}-#{ctx.run_id}.#{extension}"
    {metadata, message} = upload(ctx, bytes, name, mode)

    event = %{
      "type" => "message",
      "channel" => ctx.room_id,
      "ts" => message["id"],
      "user" => metadata["user"],
      "text" => message["text"],
      "files" => [metadata]
    }

    assert {:ok, %{signals: [fact]}} = Chat.normalize(ctx.client, event)
    assert fact.type == Signal.MessageReceived.type()
    assert fact.data["room_id"] == ctx.room_id
    assert fact.data["message_id"] == message["id"]

    assert [%{"name" => ^name, "kind" => ^kind, "resource_ref" => ref}] = fact.data["media"]
    assert ref == reference(ctx, metadata)
    assert download(ctx, ref, mode) == bytes
  end

  defp fixture_bytes(path), do: path |> File.read!() |> Base.decode64!(ignore: :whitespace)

  defp upload(ctx, bytes, filename, mode) do
    source = %{"content_base64" => Base.encode64(bytes), "filename" => filename}
    caption = LiveAPI.marker(ctx, "file")

    message =
      LiveAPI.complete(
        ctx,
        Signal.SendFile,
        %{"room_id" => ctx.room_id, "source" => source, "caption" => caption},
        mode
      )

    assert {:ok, %{"files" => [%{"id" => file_id}]}} = LiveAPI.wire_result(:send_file)

    LiveCase.on_cleanup(fn ->
      assert {:ok, _} = LiveFixture.api_request(ctx, "files.delete", [file: file_id], :cleanup)
    end)

    assert message["room_id"] == ctx.room_id and message["text"] == caption

    metadata = file_info(ctx, file_id, @file_info_attempts)
    assert metadata["name"] == filename
    assert metadata["size"] == byte_size(bytes)
    {metadata, message}
  end

  defp file_info(ctx, file_id, attempts) do
    assert {:ok, %{"file" => %{"id" => ^file_id} = metadata}} =
             LiveFixture.api_request(ctx, "files.info", file: file_id)

    # Slack can share hosted files before it fills in the metadata after scanning them.
    case {metadata["mode"], metadata["mimetype"]} do
      {"hosted", mime} when mime in [nil, ""] and attempts > 1 ->
        Process.sleep(500)
        file_info(ctx, file_id, attempts - 1)

      _ ->
        metadata
    end
  end

  defp reference(ctx, metadata) do
    url = metadata["url_private_download"] || metadata["url_private"]
    assert is_binary(url)
    %{"client_id" => ctx.client.id, "kind" => "media", "id" => url}
  end

  defp download(ctx, ref, mode) do
    result = LiveAPI.complete(ctx, Signal.DownloadFile, %{"resource_ref" => ref}, mode)
    bytes = Base.decode64!(result["content_base64"])
    assert {:ok, ^bytes} = LiveAPI.wire_result(:download_file)
    bytes
  end
end
