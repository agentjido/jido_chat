defmodule Jido.Chat.Telegram.PublicAPILiveTest do
  use ExUnit.Case, async: false

  alias Jido.Chat.{Client, Signal}
  alias Jido.Chat.Telegram.{Adapter, Transport}

  @run_live System.get_env("RUN_LIVE_TELEGRAM_TESTS") in ["1", "true", "TRUE", "yes", "on"]
  @token System.get_env("TELEGRAM_BOT_TOKEN")
  @chat_id System.get_env("TELEGRAM_TEST_CHAT_ID")
  @forum_chat_id System.get_env("TELEGRAM_TEST_FORUM_CHAT_ID")
  @thread_id System.get_env("TELEGRAM_TEST_THREAD_ID")
  @reaction System.get_env("TELEGRAM_TEST_REACTION") || "👍"
  @private_chat is_binary(@chat_id) and Regex.match?(~r/^[1-9]\d*$/, @chat_id)
  @keep_messages System.get_env("TELEGRAM_PUBLIC_API_KEEP_MESSAGES") in ["1", "true", "TRUE"]
  @trace "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
  @moduletag :live
  @moduletag :chat_public_api_live
  @moduletag timeout: 60_000
  @moduletag capture_log: true

  if not @run_live do
    @moduletag skip: "set RUN_LIVE_TELEGRAM_TESTS=true to run live Telegram tests"
  end

  if @run_live and (@token in [nil, ""] or @chat_id in [nil, ""]) do
    @moduletag skip: "set TELEGRAM_BOT_TOKEN and TELEGRAM_TEST_CHAT_ID"
  end

  # Observe the real transport. No provider responses are replaced.
  defmodule ObservedTransport do
    @behaviour Transport

    @impl true
    def call(token, method, payload, opts) do
      result = Transport.ExGramClient.call(token, method, payload, opts)
      send(Keyword.fetch!(opts, :public_api_observer), {:public_api_wire, method, payload, result})
      result
    end
  end

  setup_all do
    run_id = Integer.to_string(System.system_time(:microsecond))
    IO.puts("\nJIDO CHAT PUBLIC API LIVE RUN: #{run_id}\n")
    %{run_id: run_id}
  end

  setup ctx do
    client =
      Client.new!(Adapter,
        id: "telegram.public_api.live",
        credentials: %{token: @token},
        config: [public_api_observer: self()],
        transport: ObservedTransport
      )

    opts = if @thread_id in [nil, ""], do: [], else: [thread_id: @thread_id]
    %{client: client, room_id: to_string(@chat_id), opts: opts, label: "Jido public API #{ctx.run_id}"}
  end

  test "send_text returns a portable completion with request and trace context", ctx do
    text = "#{ctx.label}: send_text passed. Literal **plain text**."
    request_id = "public-api:#{ctx.run_id}:text"

    assert {:ok, signal} =
             Jido.Chat.send_text(
               ctx.client,
               ctx.room_id,
               text,
               ctx.opts ++ [request_id: request_id, signal_options: [extensions: %{"traceparent" => @trace}]]
             )

    result = assert_completion(ctx, signal, Signal.SendMessage, request_id)
    assert result["text"] == text
    assert signal.extensions["traceparent"] == @trace
    {payload, raw} = response("sendMessage")
    assert payload["text"] == text
    assert to_string(field(raw, "message_id")) == result["id"]
    refute Map.has_key?(payload, "rich_message")
    refute_receive {:public_api_wire, _, _, _}
  end

  test "send_text composes a rich reply and keyboard from the previous result", ctx do
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

  test "send_text supports HTML through the same public function", ctx do
    text = "<b>#{ctx.label}: HTML passed.</b>"
    assert {:ok, signal} = Jido.Chat.send_text(ctx.client, ctx.room_id, text, ctx.opts ++ [format: :html])
    assert_completion(ctx, signal, Signal.SendMessage)
    {payload, raw} = response("sendRichMessage")
    assert payload["rich_message"] == %{"html" => text}
    assert field(raw, "rich_message")
  end

  @tag skip: if(@private_chat, do: false, else: "draft delivery needs a positive private chat ID")
  test "stream_text consumes a lazy source once and selects plain drafts", ctx do
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
    refute_receive {:public_api_wire, _, _, _}
  end

  @tag skip: if(@private_chat, do: false, else: "draft delivery needs a positive private chat ID")
  test "stream_text repairs Markdown previews and persists exact final content", ctx do
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
    refute_receive {:public_api_wire, _, _, _}
  end

  test "stream_text can select edits and keeps one provider message ID", ctx do
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
    refute_receive {:public_api_wire, _, _, _}
  end

  test "stream_text respects Client delivery config and flushes coalesced final text", ctx do
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
    refute_receive {:public_api_wire, _, _, _}
  end

  test "send_file uploads inline document bytes and returns a downloadable reference", ctx do
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

  test "send_file composes a local upload with reuse of the returned media reference", ctx do
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

  test "send_file selects image delivery and its provider response normalizes to a Signal", ctx do
    source = %{
      "content_base64" =>
        File.read!(Path.expand("../../../../examples/providers/telegram/photo.png.b64", __DIR__)) |> String.trim(),
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
    assert_round_trip(fact)
  end

  test "capabilities declares supported public operations without network calls", ctx do
    capabilities = Jido.Chat.capabilities(ctx.client)

    for operation <- [
          :send_message,
          :stream_text,
          :send_file,
          :edit_message,
          :delete_message,
          :download_file,
          :add_reaction,
          :remove_reaction,
          :fetch_metadata,
          :start_typing,
          :create_thread
        ] do
      assert capabilities[operation] == :native
    end

    assert capabilities[:fetch_messages] == :unsupported
    assert map_size(capabilities) == length(Jido.Chat.actions())
    refute_receive {:public_api_wire, _, _, _}
  end

  test "edit_message uses a sent message ID and clears its keyboard", ctx do
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

  test "delete_message removes a sent message and a repeated delete is rejected", ctx do
    assert {:ok, sent} = Jido.Chat.send_text(ctx.client, ctx.room_id, "#{ctx.label}: delete fixture", ctx.opts)
    # This test deletes its own fixture, including when messages are otherwise retained.
    original = assert_result(ctx, sent, Signal.SendMessage)
    response("sendMessage")
    request_id = "public-api:#{ctx.run_id}:delete"

    assert {:ok, deleted} = Jido.Chat.delete_message(ctx.client, ctx.room_id, original["id"], request_id: request_id)
    assert assert_result(ctx, deleted, Signal.DeleteMessage, request_id) == %{"acknowledged" => true}
    {payload, true} = response("deleteMessage")
    assert payload["message_id"] == original["id"]

    assert {:error, %Jido.Chat.Error{signal: failed}} =
             Jido.Chat.delete_message(ctx.client, ctx.room_id, original["id"])

    assert failed.type == Signal.DeleteMessage.type() <> ".failed"
    assert failed.data["outcome"] == "rejected"
    assert_round_trip(failed)
    assert_receive {:public_api_wire, "deleteMessage", _, {:error, _}}
  end

  test "add_reaction and remove_reaction compose with a sent message ID", ctx do
    assert {:ok, sent} = Jido.Chat.send_text(ctx.client, ctx.room_id, "#{ctx.label}: reaction fixture", ctx.opts)
    original = assert_completion(ctx, sent, Signal.SendMessage)
    response("sendMessage")

    assert {:ok, added} = Jido.Chat.add_reaction(ctx.client, ctx.room_id, original["id"], @reaction)
    assert assert_result(ctx, added, Signal.AddReaction) == %{"acknowledged" => true}
    {addition, true} = response("setMessageReaction")
    assert addition["message_id"] == original["id"]
    assert addition["reaction"] == [%{"type" => "emoji", "emoji" => @reaction}]

    assert {:ok, removed} = Jido.Chat.remove_reaction(ctx.client, ctx.room_id, original["id"], @reaction)
    assert assert_result(ctx, removed, Signal.RemoveReaction) == %{"acknowledged" => true}
    {removal, true} = response("setMessageReaction")
    assert removal["message_id"] == original["id"]
    assert removal["reaction"] == []
  end

  test "fetch_metadata returns room data from the real provider with trace context", ctx do
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
    refute_receive {:public_api_wire, _, _, _}
  end

  test "start_typing sends one notice with the configured thread and returns an acknowledgement", ctx do
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
    refute_receive {:public_api_wire, _, _, _}
  end

  @tag skip:
         if(@forum_chat_id in [nil, ""],
           do: "set TELEGRAM_TEST_FORUM_CHAT_ID for successful topic creation",
           else: false
         )
  test "create_thread returns a real topic ID used by start_typing and send_text", ctx do
    forum = %{ctx | room_id: @forum_chat_id, opts: []}
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
    refute_receive {:public_api_wire, _, _, _}
  end

  test "create_thread returns a safe failure Signal for an invalid destination", ctx do
    request_id = "public-api:#{ctx.run_id}:thread-rejected"

    assert {:error, %Jido.Chat.Error{signal: failed}} =
             Jido.Chat.create_thread(ctx.client, "0", "Invalid destination check", request_id: request_id)

    assert failed.type == Signal.CreateThread.type() <> ".failed"
    assert failed.data["request_id"] == request_id
    assert failed.data["code"] == "provider_failure"
    assert failed.data["outcome"] == "rejected"
    assert_round_trip(failed)
    assert_receive {:public_api_wire, "createForumTopic", %{"chat_id" => "0"}, {:error, _}}
    refute_receive {:public_api_wire, _, _, _}
  end

  test "invalid public input fails before network calls or stream consumption", ctx do
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
    assert_round_trip(failed)
    assert {:error, _} = Jido.Chat.edit_message(ctx.client, ctx.room_id, "1", "invalid", thread_id: "cannot-move")
    assert {:error, _} = Jido.Chat.delete_message(ctx.client, ctx.room_id, "")
    assert {:error, _} = Jido.Chat.add_reaction(ctx.client, ctx.room_id, "1", "")
    assert {:error, _} = Jido.Chat.remove_reaction(ctx.client, ctx.room_id, "1", @reaction, unknown: true)
    assert {:error, _} = Jido.Chat.fetch_metadata(ctx.client, "")
    assert {:error, _} = Jido.Chat.start_typing(ctx.client, ctx.room_id, thread_id: "")
    assert {:error, _} = Jido.Chat.start_typing(ctx.client, ctx.room_id, interval_ms: 1000)
    assert {:error, _} = Jido.Chat.create_thread(ctx.client, ctx.room_id, "")
    assert {:error, _} = Jido.Chat.create_thread(ctx.client, ctx.room_id, "Invalid", thread_id: "existing")
    foreign_ref = %{"client_id" => "another-client", "kind" => "media", "id" => "telegram://file/invalid"}

    assert {:error, %Jido.Chat.Errors.Contract{code: :context_mismatch}} =
             Jido.Chat.download_file(ctx.client, foreign_ref)

    refute_receive :invalid_source_read
    refute_receive {:public_api_wire, _, _, _}
  end

  test "send_text turns a real provider rejection into a safe failure Signal", ctx do
    request_id = "public-api:#{ctx.run_id}:rejected"

    assert {:error, %Jido.Chat.Error{signal: failed}} =
             Jido.Chat.send_text(ctx.client, "0", "Invalid destination check", request_id: request_id)

    assert failed.type == Signal.SendMessage.type() <> ".failed"
    assert failed.data["request_id"] == request_id
    assert failed.data["code"] == "provider_failure"
    assert failed.data["outcome"] == "rejected"
    assert_round_trip(failed)
    assert_receive {:public_api_wire, "sendMessage", %{"chat_id" => "0"}, {:error, _}}
    refute_receive {:public_api_wire, _, _, _}
  end

  test "execute pulls a real Telegram batch through the shared normalization boundary", ctx do
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
    {_payload, updates} = response("getUpdates")
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
    refute_receive {:public_api_wire, _, _, _}
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
    assert signal.type == definition.type() <> ".completed"
    assert signal.data["operation"] == definition.type()
    assert signal.data["client_id"] == ctx.client.id
    assert is_binary(signal.extensions["jidocausationid"])

    if request_id,
      do: assert(signal.data["request_id"] == request_id),
      else: assert(Jido.Id.uuid7?(signal.data["request_id"]))

    assert_round_trip(signal)
    signal.data["result"]
  end

  defp assert_round_trip(signal) do
    assert {:ok, json} = Jido.Signal.Codec.serialize(signal)
    assert {:ok, ^signal} = Jido.Signal.Catalog.decode(Jido.Chat.Telegram.catalog(), json)
    refute json =~ to_string(@token)
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

  defp cleanup(ctx, message_id) do
    unless @keep_messages do
      on_exit(fn ->
        request_id = "cleanup:#{message_id}"
        assert {:ok, completed} = Jido.Chat.delete_message(ctx.client, ctx.room_id, message_id, request_id: request_id)
        assert assert_result(ctx, completed, Signal.DeleteMessage, request_id) == %{"acknowledged" => true}
      end)
    end
  end

  defp response(method) do
    assert_receive {:public_api_wire, ^method, payload, {:ok, raw}}, 2_000
    {payload, raw}
  end

  defp field(map, key) do
    Map.get(map, key) ||
      Enum.find_value(Map.to_list(map), fn {k, v} -> if is_atom(k) and Atom.to_string(k) == key, do: v end)
  end
end
