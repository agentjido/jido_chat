defmodule Jido.Chat.Telegram.LivePublicAPI do
  @moduledoc false
  import ExUnit.Assertions
  import ExUnit.Callbacks, only: [on_exit: 1]
  import Jido.Chat.Telegram.LiveFixture, only: [cleanup: 2, field: 2, fixture_path: 1, forget_cleanup: 2]
  alias Jido.Chat.{LiveCase, Signal}

  @trace "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

  def p02(ctx) do
    assert {:ok, root} = Jido.Chat.send_text(ctx.client, ctx.room_id, "#{ctx.label}: reply root", ctx.opts)
    parent = assert_completion(ctx, root, Signal.SendMessage)
    response("sendMessage")
    text = "**#{ctx.label}: Markdown reply passed.**"
    keyboard = %{"rows" => [[%{"text" => "SDK check", "value" => "public-api:#{ctx.run_id}"}]]}

    assert {:ok, reply} =
             Jido.Chat.send_text(
               ctx.client,
               ctx.room_id,
               text,
               ctx.opts ++ [format: :markdown, reply_to_id: parent["id"], keyboard: keyboard]
             )

    result = assert_completion(ctx, reply, Signal.SendMessage)
    {payload, raw} = response("sendRichMessage")
    assert payload["rich_message"] == %{"markdown" => text}
    assert payload["reply_parameters"] == %{"message_id" => parent["id"]}

    assert get_in(payload, ["reply_markup", "inline_keyboard", Access.at(0), Access.at(0), "callback_data"]) ==
             "public-api:#{ctx.run_id}"

    assert result["reply_to_id"] == parent["id"]
    assert to_string(field(field(raw, "reply_to_message"), "message_id")) == parent["id"]
    assert field(raw, "rich_message")
  end

  def p03(ctx) do
    text = "<b>#{ctx.label}: HTML passed.</b>"
    assert {:ok, signal} = Jido.Chat.send_text(ctx.client, ctx.room_id, text, ctx.opts ++ [format: :html])
    assert_completion(ctx, signal, Signal.SendMessage)
    {payload, raw} = response("sendRichMessage")
    assert payload["rich_message"] == %{"html" => text}
    assert field(raw, "rich_message")
  end

  def p04(ctx) do
    owner = self()
    chunks = ["#{ctx.label}: plain draft", " stream passed."]

    source =
      Stream.resource(
        fn -> chunks end,
        fn
          [] ->
            {:halt, []}

          [chunk | rest] ->
            send(owner, {:source_chunk, chunk, self()})
            {[chunk], rest}
        end,
        fn _ -> send(owner, :source_closed) end
      )

    assert {:ok, signal} =
             Jido.Chat.stream_text(ctx.client, ctx.room_id, source, ctx.opts ++ [update_interval_ms: 0])

    result = assert_completion(ctx, signal, Signal.StreamText)
    {first, true} = response("sendMessageDraft")
    {second, true} = response("sendMessageDraft")
    {final, _} = response("sendMessage")
    assert first["draft_id"] == second["draft_id"]
    assert first["text"] == hd(chunks)
    assert second["text"] == Enum.join(chunks)
    assert final["text"] == result["text"] and result["text"] == Enum.join(chunks)

    assert_receive {:source_chunk, first_chunk, execution_pid}
    assert_receive {:source_chunk, second_chunk, ^execution_pid}
    assert [first_chunk, second_chunk] == chunks
    assert_receive :source_closed
    refute Process.alive?(execution_pid)
    refute_receive {:source_chunk, _, _}
    refute_receive {:telegram_live_wire, _, _, _}
  end

  def p05(ctx) do
    chunks = ["**#{ctx.label}: rich draft", " stream passed.**"]

    assert {:ok, signal} =
             Jido.Chat.stream_text(
               ctx.client,
               ctx.room_id,
               chunks,
               ctx.opts ++ [format: :markdown, update_interval_ms: 0]
             )

    assert_completion(ctx, signal, Signal.StreamText)
    {first, true} = response("sendRichMessageDraft")
    {second, true} = response("sendRichMessageDraft")
    {final, raw} = response("sendRichMessage")
    assert first["draft_id"] == second["draft_id"]
    assert first["rich_message"] == %{"markdown" => hd(chunks) <> "**"}
    assert second["rich_message"] == %{"markdown" => Enum.join(chunks)}
    assert final["rich_message"] == %{"markdown" => Enum.join(chunks)}
    assert field(raw, "rich_message")
    refute_receive {:telegram_live_wire, _, _, _}
  end

  def p06(ctx) do
    chunks = ["#{ctx.label}: edit stream", " update", " passed."]

    assert {:ok, signal} =
             Jido.Chat.stream_text(
               ctx.client,
               ctx.room_id,
               Stream.map(chunks, & &1),
               ctx.opts ++ [update_interval_ms: 0, options: [stream_delivery: :edit]]
             )

    result = assert_completion(ctx, signal, Signal.StreamText)
    {sent, raw} = response("sendMessage")
    {edit, _} = response("editMessageText")
    {final, _} = response("editMessageText")
    assert sent["text"] == hd(chunks)
    assert edit["text"] == Enum.take(chunks, 2) |> Enum.join()
    assert final["text"] == result["text"] and result["text"] == Enum.join(chunks)
    assert edit["message_id"] == final["message_id"] and final["message_id"] == result["id"]
    assert to_string(field(raw, "message_id")) == result["id"]
    refute_receive {:telegram_live_wire, _, _, _}
  end

  def p07(ctx) do
    client = %{ctx.client | config: Keyword.put(ctx.client.config, :stream_delivery, :edit)}
    chunks = ["#{ctx.label}: coalesced", " edit stream", " passed."]

    assert {:ok, signal} =
             Jido.Chat.stream_text(client, ctx.room_id, chunks, ctx.opts ++ [update_interval_ms: 60_000])

    result = assert_completion(ctx, signal, Signal.StreamText)
    {first, _} = response("sendMessage")
    {last, _} = response("editMessageText")
    assert first["text"] == hd(chunks)
    assert last["text"] == result["text"] and result["text"] == Enum.join(chunks)
    refute Keyword.has_key?(ctx.client.config, :stream_delivery)
    refute_receive {:telegram_live_wire, _, _, _}
  end

  def p08(ctx) do
    bytes = Jason.encode!(%{"api" => "Jido.Chat.send_file", "run" => ctx.run_id})
    source = %{"content_base64" => Base.encode64(bytes), "filename" => "jido-public-api.json"}
    caption = "#{ctx.label}: inline send_file passed."

    assert {:ok, signal} = Jido.Chat.send_file(ctx.client, ctx.room_id, source, ctx.opts ++ [caption: caption])
    result = assert_completion(ctx, signal, Signal.SendFile)
    assert result["text"] == caption
    assert [%{"kind" => "file", "resource_ref" => ref}] = result["media"]
    assert ref["client_id"] == ctx.client.id and ref["kind"] == "media"
    {payload, raw} = response("sendDocument")
    assert payload["caption"] == caption
    assert field(field(raw, "document"), "file_name") == "jido-public-api.json"
    assert download(ctx, ref) == bytes
  end

  def p09(ctx) do
    bytes = "#{ctx.label}: local file and provider reference passed.\n"
    file = Path.join(System.tmp_dir!(), "jido-public-api-#{ctx.run_id}.txt")
    File.write!(file, bytes)
    on_exit(fn -> File.rm(file) end)
    source = %{"client_id" => ctx.client.id, "kind" => "file", "id" => file}

    assert {:ok, uploaded} =
             Jido.Chat.send_file(ctx.client, ctx.room_id, source, ctx.opts ++ [caption: "#{ctx.label}: local file"])

    original = assert_completion(ctx, uploaded, Signal.SendFile)
    [media] = original["media"]

    assert {:ok, reused} =
             Jido.Chat.send_file(
               ctx.client,
               ctx.room_id,
               media["resource_ref"],
               ctx.opts ++ [caption: "#{ctx.label}: provider reference reused"]
             )

    copied = assert_completion(ctx, reused, Signal.SendFile)
    assert original["id"] != copied["id"]
    [copy] = copied["media"]
    assert download(ctx, media["resource_ref"]) == bytes
    assert download(ctx, copy["resource_ref"]) == bytes
  end

  def p10(ctx) do
    source = %{
      "content_base64" => File.read!(fixture_path("photo.png.b64")) |> String.trim(),
      "filename" => "jido-public-api.png"
    }

    caption = "#{ctx.label}: image send_file passed."

    assert {:ok, signal} =
             Jido.Chat.send_file(ctx.client, ctx.room_id, source, ctx.opts ++ [media_kind: :image, caption: caption])

    result = assert_completion(ctx, signal, Signal.SendFile)
    assert [%{"kind" => "image", "resource_ref" => ref}] = result["media"]
    {payload, raw} = response("sendPhoto")
    assert payload["caption"] == caption
    assert byte_size(download(ctx, ref)) > 0
    assert {:ok, delivery} = Jido.Chat.normalize(ctx.client, %{message: raw})
    assert [fact] = delivery.signals
    assert fact.type == Signal.MessageReceived.type()
    assert fact.data["text"] == caption
    assert [%{"kind" => "image", "width" => 64, "height" => 64}] = fact.data["media"]
    assert_round_trip(ctx, fact)
  end

  def p11(ctx) do
    assert Jido.Chat.capabilities(ctx.client) == ctx.profile.expected_capabilities()
    refute_receive {:telegram_live_wire, _, _, _}
  end

  def p12(ctx) do
    keyboard = %{"rows" => [[%{"text" => "Read docs", "url" => "https://hexdocs.pm/jido_chat"}]]}

    assert {:ok, sent} =
             Jido.Chat.send_text(ctx.client, ctx.room_id, "#{ctx.label}: before edit", ctx.opts ++ [keyboard: keyboard])

    original = assert_completion(ctx, sent, Signal.SendMessage)
    response("sendMessage")
    text = "#{ctx.label}: edit_message passed. Keyboard removed."
    request_id = "public-api:#{ctx.run_id}:edit"

    assert {:ok, edited} =
             Jido.Chat.edit_message(ctx.client, ctx.room_id, original["id"], text,
               request_id: request_id,
               keyboard: %{"rows" => []},
               signal_options: [extensions: %{"traceparent" => @trace}]
             )

    result = assert_result(ctx, edited, Signal.EditMessage, request_id)
    assert result["id"] == original["id"] and result["room_id"] == ctx.room_id
    assert result["status"] == "updated" and result["text"] == text
    assert edited.extensions["traceparent"] == @trace
    {payload, raw} = response("editMessageText")
    assert payload["reply_markup"] == %{"inline_keyboard" => []}
    assert to_string(field(raw, "message_id")) == original["id"]
    assert field(raw, "text") == text
    assert field(raw, "reply_markup") == nil
  end

  def p13(ctx) do
    assert {:ok, sent} = Jido.Chat.send_text(ctx.client, ctx.room_id, "#{ctx.label}: delete fixture", ctx.opts)
    original = assert_result(ctx, sent, Signal.SendMessage)
    cleanup(ctx, original["id"])
    response("sendMessage")
    request_id = "public-api:#{ctx.run_id}:delete"

    assert {:ok, deleted} = Jido.Chat.delete_message(ctx.client, ctx.room_id, original["id"], request_id: request_id)
    forget_cleanup(ctx, original["id"])
    assert assert_result(ctx, deleted, Signal.DeleteMessage, request_id) == %{"acknowledged" => true}
    {payload, true} = response("deleteMessage")
    assert payload["message_id"] == original["id"]

    assert {:error, %Jido.Chat.Error{signal: failed}} =
             Jido.Chat.delete_message(ctx.client, ctx.room_id, original["id"])

    assert failed.type == Signal.DeleteMessage.type() <> ".failed"
    assert failed.data["code"] == "provider_failure"
    assert failed.data["outcome"] == "rejected"
    assert_round_trip(ctx, failed)
    assert_receive {:telegram_live_wire, "deleteMessage", _, {:error, _}}
  end

  def p14(ctx) do
    assert {:ok, sent} = Jido.Chat.send_text(ctx.client, ctx.room_id, "#{ctx.label}: reaction fixture", ctx.opts)
    original = assert_completion(ctx, sent, Signal.SendMessage)
    response("sendMessage")

    assert {:ok, added} = Jido.Chat.add_reaction(ctx.client, ctx.room_id, original["id"], ctx.reaction)
    assert assert_result(ctx, added, Signal.AddReaction) == %{"acknowledged" => true}
    {addition, true} = response("setMessageReaction")
    assert addition["message_id"] == original["id"]
    assert addition["reaction"] == [%{"type" => "emoji", "emoji" => ctx.reaction}]

    assert {:ok, removed} = Jido.Chat.remove_reaction(ctx.client, ctx.room_id, original["id"], ctx.reaction)
    assert assert_result(ctx, removed, Signal.RemoveReaction) == %{"acknowledged" => true}
    {removal, true} = response("setMessageReaction")
    assert removal["message_id"] == original["id"]
    assert removal["reaction"] == []
  end

  def p15(ctx) do
    request_id = "public-api:#{ctx.run_id}:metadata"

    assert {:ok, signal} =
             Jido.Chat.fetch_metadata(ctx.client, ctx.room_id,
               request_id: request_id,
               signal_options: [extensions: %{"traceparent" => @trace}]
             )

    result = assert_result(ctx, signal, Signal.FetchMetadata, request_id)
    assert signal.extensions["traceparent"] == @trace
    {payload, raw} = response("getChat")
    assert payload == %{"chat_id" => ctx.room_id}
    assert result["id"] == ctx.room_id
    assert to_string(field(raw, "id")) == result["id"]

    expected_kind =
      case field(raw, "type") do
        "private" -> "direct"
        "channel" -> "channel"
        _ -> "group"
      end

    assert result["kind"] == expected_kind
    assert result["name"] == (field(raw, "title") || field(raw, "username") || field(raw, "first_name"))
    refute_receive {:telegram_live_wire, _, _, _}
  end

  def p16(ctx) do
    request_id = "public-api:#{ctx.run_id}:typing"

    assert {:ok, signal} =
             Jido.Chat.start_typing(
               ctx.client,
               ctx.room_id,
               ctx.opts ++ [request_id: request_id, signal_options: [extensions: %{"traceparent" => @trace}]]
             )

    assert assert_result(ctx, signal, Signal.StartTyping, request_id) == %{"acknowledged" => true}
    assert signal.extensions["traceparent"] == @trace
    {payload, true} = response("sendChatAction")
    assert payload["chat_id"] == ctx.room_id
    assert payload["action"] == "typing"
    assert payload["message_thread_id"] == ctx.opts[:thread_id]
    refute_receive {:telegram_live_wire, _, _, _}
  end

  def p17(ctx) do
    forum = %{ctx | room_id: ctx.forum_id, opts: []}
    name = "Jido public API #{ctx.run_id}"
    request_id = "public-api:#{ctx.run_id}:thread"

    assert {:ok, created} =
             Jido.Chat.create_thread(forum.client, forum.room_id, name,
               request_id: request_id,
               signal_options: [extensions: %{"traceparent" => @trace}]
             )

    topic = assert_result(forum, created, Signal.CreateThread, request_id)
    assert topic["room_id"] == forum.room_id and topic["name"] == name
    assert topic["id"] =~ ~r/^\d+$/
    assert created.extensions["traceparent"] == @trace
    {payload, raw} = response("createForumTopic")
    assert payload == %{"chat_id" => forum.room_id, "name" => name}
    assert to_string(field(raw, "message_thread_id")) == topic["id"]
    assert field(raw, "name") == name

    assert {:ok, metadata} = Jido.Chat.fetch_metadata(forum.client, forum.room_id)
    room = assert_result(forum, metadata, Signal.FetchMetadata)
    assert room["id"] == forum.room_id and room["kind"] == "group"
    {_, chat} = response("getChat")
    assert field(chat, "is_forum") == true

    assert {:ok, typing} = Jido.Chat.start_typing(forum.client, forum.room_id, thread_id: topic["id"])
    assert assert_result(forum, typing, Signal.StartTyping) == %{"acknowledged" => true}
    {typing_payload, true} = response("sendChatAction")
    assert typing_payload["message_thread_id"] == topic["id"]

    assert {:ok, sent} =
             Jido.Chat.send_text(forum.client, forum.room_id, "#{ctx.label}: new topic passed.", thread_id: topic["id"])

    message = assert_completion(forum, sent, Signal.SendMessage)
    assert message["thread_id"] == topic["id"]
    {sent_payload, sent_raw} = response("sendMessage")
    assert sent_payload["message_thread_id"] == topic["id"]
    assert to_string(field(sent_raw, "message_thread_id")) == topic["id"]
    refute_receive {:telegram_live_wire, _, _, _}
  end

  def p18(ctx) do
    request_id = "public-api:#{ctx.run_id}:thread-rejected"

    assert {:error, %Jido.Chat.Error{signal: failed}} =
             Jido.Chat.create_thread(ctx.client, "0", "Invalid destination check", request_id: request_id)

    assert failed.type == Signal.CreateThread.type() <> ".failed"
    assert failed.data["request_id"] == request_id
    assert failed.data["code"] == "provider_failure"
    assert failed.data["outcome"] == "rejected"
    assert_round_trip(ctx, failed)
    assert_receive {:telegram_live_wire, "createForumTopic", %{"chat_id" => "0"}, {:error, _}}
    refute_receive {:telegram_live_wire, _, _, _}
  end

  def p19(ctx) do
    owner = self()

    source =
      Stream.map(["must not be read"], fn text ->
        send(owner, :invalid_source_read)
        text
      end)

    assert {:error, _} = Jido.Chat.send_text(ctx.client, ctx.room_id, "invalid", unknown_option: true)
    assert {:error, _} = Jido.Chat.send_file(ctx.client, ctx.room_id, %{"content_base64" => "bad", "filename" => "bad"})
    assert {:error, _} = Jido.Chat.stream_text(ctx.client, ctx.room_id, source, update_interval_ms: -1)
    assert {:error, %Jido.Chat.Error{signal: failed}} = Jido.Chat.stream_text(ctx.client, ctx.room_id, [])
    assert failed.data["outcome"] == "not_attempted"
    assert_round_trip(ctx, failed)
    assert {:error, _} = Jido.Chat.edit_message(ctx.client, ctx.room_id, "1", "invalid", thread_id: "cannot-move")
    assert {:error, _} = Jido.Chat.delete_message(ctx.client, ctx.room_id, "")
    assert {:error, _} = Jido.Chat.add_reaction(ctx.client, ctx.room_id, "1", "")
    assert {:error, _} = Jido.Chat.remove_reaction(ctx.client, ctx.room_id, "1", ctx.reaction, unknown: true)
    assert {:error, _} = Jido.Chat.fetch_metadata(ctx.client, "")
    assert {:error, _} = Jido.Chat.start_typing(ctx.client, ctx.room_id, thread_id: "")
    assert {:error, _} = Jido.Chat.start_typing(ctx.client, ctx.room_id, interval_ms: 1000)
    assert {:error, _} = Jido.Chat.create_thread(ctx.client, ctx.room_id, "")
    assert {:error, _} = Jido.Chat.create_thread(ctx.client, ctx.room_id, "Invalid", thread_id: "existing")
    foreign_ref = %{"client_id" => "another-client", "kind" => "media", "id" => "telegram://file/invalid"}

    assert {:error, %Jido.Chat.Errors.Contract{code: :context_mismatch}} =
             Jido.Chat.download_file(ctx.client, foreign_ref)

    refute_receive :invalid_source_read
    refute_receive {:telegram_live_wire, _, _, _}
  end

  def p20(ctx) do
    request_id = "public-api:#{ctx.run_id}:rejected"

    assert {:error, %Jido.Chat.Error{signal: failed}} =
             Jido.Chat.send_text(ctx.client, "0", "Invalid destination check", request_id: request_id)

    assert failed.type == Signal.SendMessage.type() <> ".failed"
    assert failed.data["request_id"] == request_id
    assert failed.data["code"] == "provider_failure"
    assert failed.data["outcome"] == "rejected"
    assert_round_trip(ctx, failed)
    assert_receive {:telegram_live_wire, "sendMessage", %{"chat_id" => "0"}, {:error, _}}
    refute_receive {:telegram_live_wire, _, _, _}
  end

  def p21(ctx) do
    alias Jido.Chat.Telegram

    request =
      Telegram.Signal.FetchUpdates.new!(%{
        "client_id" => ctx.client.id,
        "request_id" => "public-api:#{ctx.run_id}:updates",
        "limit" => 100,
        "timeout" => 0
      })

    assert {:ok, completed} = Jido.Chat.execute(ctx.client, request, timeout: 30_000)
    result = assert_result(ctx, completed, Telegram.Signal.FetchUpdates, request.data["request_id"])
    {payload, updates} = response("getUpdates")
    refute Map.has_key?(payload, "offset")
    assert is_list(updates)
    assert {:ok, delivery} = Jido.Chat.normalize(ctx.client, updates)

    pulled =
      Enum.map(result["signals"], fn wire ->
        assert {:ok, signal} = Jido.Signal.Catalog.decode(Telegram.catalog(), wire)
        {signal.type, signal.data, signal.source, signal.subject}
      end)

    assert pulled == Enum.map(delivery.signals, &{&1.type, &1.data, &1.source, &1.subject})
    assert result["delivery_id"] == delivery.id
    ids = Enum.map(updates, &field(&1, "update_id"))
    assert result["next_offset"] == if(ids == [], do: nil, else: Enum.max(ids) + 1)
    refute_receive {:telegram_live_wire, _, _, _}
  end

  defp assert_completion(ctx, signal, definition, request_id \\ nil) do
    result = signal.data["result"]
    # Register cleanup before assertions so later assertion failures do not leave messages.
    if is_map(result) and is_binary(result["id"]), do: cleanup(ctx, result["id"])
    result = assert_result(ctx, signal, definition, request_id)
    assert result["room_id"] == ctx.room_id
    assert result["id"] =~ ~r/^\d+$/
    result
  end

  defp assert_result(ctx, signal, definition, request_id \\ nil) do
    id = signal.data["request_id"]
    if is_nil(request_id), do: assert(Jido.Id.uuid7?(id))
    result = LiveCase.assert_completion(ctx.client, signal, definition, request_id || id)
    assert {:ok, json} = Jido.Signal.Codec.serialize(signal)
    refute json =~ ctx.client.credentials.token
    result
  end

  defp assert_round_trip(ctx, signal) do
    assert {:ok, json} = Jido.Signal.Codec.serialize(signal)
    assert {:ok, ^signal} = Jido.Signal.Catalog.decode(Jido.Chat.Telegram.catalog(), json)
    refute json =~ ctx.client.credentials.token
  end

  defp download(ctx, ref) do
    request_id = "download:#{System.unique_integer([:positive])}"

    assert {:ok, completed} =
             Jido.Chat.download_file(ctx.client, ref,
               request_id: request_id,
               signal_options: [extensions: %{"traceparent" => @trace}]
             )

    result = assert_result(ctx, completed, Signal.DownloadFile, request_id)
    assert completed.extensions["traceparent"] == @trace
    Base.decode64!(result["content_base64"])
  end

  def response(method) do
    assert_receive {:telegram_live_wire, ^method, payload, {:ok, raw}}, 2_000
    {payload, raw}
  end
end
