defmodule Jido.Chat.Telegram.AdapterContractTest do
  use Covenant.Case, component: "jido_chat_telegram.adapter", async: true
  @moduletag capture_log: true
  alias Jido.Chat
  alias Jido.Chat.Telegram
  alias Jido.Chat.Telegram.ContractFixtures, as: F

  @tag obligation: "jido_chat_telegram.adapter.I1"
  test "public exports, exact capabilities, configured discovery, and startup metadata stay fixed" do
    manifest = F.manifest()
    for {name, expected} <- manifest["exports"], do: assert(F.public_exports(F.module(name)) == expected)
    assert Telegram.adapter() == Telegram.Adapter
    assert Telegram.Adapter.channel_type() == :telegram
    assert Telegram.Adapter.default_transport() == Telegram.Transport.ExGramClient
    assert :ok = Chat.AdapterTestKit.Assertions.assert_capability_coherence(Telegram.Adapter)

    expected =
      Map.new(manifest["native_operations"], &{String.to_atom(&1), :native})
      |> Map.merge(Map.new(manifest["unsupported_operations"], &{String.to_atom(&1), :unsupported}))

    core_definitions = Chat.signal_definitions()

    for id <- ["alpha", "beta"] do
      client = F.client(id)
      assert Chat.capabilities(client) == expected
      assert client.source == "urn:jido:chat:client:" <> Base.url_encode64(id, padding: false)
      assert client.credentials.token == "fixture-token:" <> id
      assert client.config[:bot_id] == 99
      assert client.transport == F.Transport
      refute inspect(client) =~ "fixture-token"
      assert Enum.sort(Enum.map(Chat.event_definitions(client), &inspect/1)) == Enum.sort(manifest["events"])
      assert Enum.sort(Enum.map(Telegram.actions(), &inspect/1)) == F.cases() |> Enum.map(& &1["action"]) |> Enum.sort()
      assert length(Chat.operations(client)) == 37
      assert length(Chat.actions(client)) == 37
      assert length(Chat.signal_definitions(client)) == 128

      assert Telegram.operations() ==
               Enum.sort(
                 Enum.map(F.cases(), fn row ->
                   action = F.module(row["action"])
                   {action.signal_definition(), action}
                 end)
               )

      assert Chat.Adapter.operations(Telegram.Adapter) == Telegram.operations()
      assert Telegram.Adapter.event_definitions() == Telegram.event_definitions()
      assert %Jido.Signal.Catalog{} = Chat.catalog(client)
    end

    assert Chat.signal_definitions() == core_definitions
    spec = Application.spec(:jido_chat)
    assert Keyword.get(spec, :mod, []) == []
    assert Keyword.get(spec, :registered, []) == []
    assert :ex_gram in Keyword.fetch!(spec, :optional_applications)
    refute :covenant in Keyword.fetch!(spec, :applications)
    refute_receive {:telegram_contract_wire, _, _, _, _, _}
  end

  @tag obligation: "jido_chat_telegram.adapter.I2"
  test "core text, edits, acknowledgements, metadata, direct rooms, and topics use the declared wire fields" do
    client = F.client()
    keyboard = %{"rows" => [[%{"text" => "Confirm", "value" => "confirm"}]]}

    for {format, method, text_field} <- [
          {"plain", "sendMessage", "text"},
          {"markdown", "sendRichMessage", "rich_message"},
          {"html", "sendRichMessage", "rich_message"}
        ] do
      fields = %{
        "room_id" => "123",
        "text" => "Hello",
        "format" => format,
        "thread_id" => "7",
        "reply_to_id" => "9",
        "keyboard" => keyboard
      }

      assert {:ok, %{signal: completed}} = F.run(Chat.SendMessage, client, fields)
      assert completed.data["result"]["id"] == "42"
      assert completed.data["result"]["room_id"] == "123"
      assert completed.data["result"]["reply_to_id"] == "9"
      assert_receive {:telegram_contract_wire, _, ^method, payload, _, _}
      assert payload["chat_id"] == "123"
      assert payload["message_thread_id"] == "7"
      assert payload["reply_parameters"] == %{"message_id" => "9"}
      assert payload["reply_markup"] == %{"inline_keyboard" => [[%{"text" => "Confirm", "callback_data" => "confirm"}]]}
      assert payload[text_field] == if(format == "plain", do: "Hello", else: %{format => "Hello"})
      assert F.round_trip(completed) == completed
    end

    assert {:ok, _} =
             F.run(Chat.EditMessage, client, %{
               "room_id" => "123",
               "message_id" => "42",
               "text" => "Done",
               "keyboard" => %{"rows" => []}
             })

    assert_receive {:telegram_contract_wire, _, "editMessageText",
                    %{"message_id" => "42", "reply_markup" => %{"inline_keyboard" => []}}, _, _}

    for {action, fields, method, payload} <- [
          {Chat.DeleteMessage, %{"room_id" => "123", "message_id" => "42"}, "deleteMessage",
           %{"chat_id" => "123", "message_id" => "42"}},
          {Chat.StartTyping, %{"room_id" => "123", "thread_id" => "7"}, "sendChatAction",
           %{"chat_id" => "123", "message_thread_id" => "7", "action" => "typing"}},
          {Chat.AddReaction, %{"room_id" => "123", "message_id" => "42", "reaction" => "👍"}, "setMessageReaction",
           %{"chat_id" => "123", "message_id" => "42", "reaction" => [%{"type" => "emoji", "emoji" => "👍"}]}},
          {Chat.RemoveReaction, %{"room_id" => "123", "message_id" => "42", "reaction" => "👍"}, "setMessageReaction",
           %{"chat_id" => "123", "message_id" => "42", "reaction" => []}},
          {Chat.FetchMetadata, %{"room_id" => "123"}, "getChat", %{"chat_id" => "123"}},
          {Chat.OpenDm, %{"user_id" => "123"}, "getChat", %{"chat_id" => "123"}},
          {Chat.CreateThread, %{"room_id" => "123", "name" => "Support"}, "createForumTopic",
           %{"chat_id" => "123", "name" => "Support"}}
        ] do
      assert {:ok, %{signal: completed}} = F.run(action, client, fields)
      assert_receive {:telegram_contract_wire, _, ^method, ^payload, _, _}
      assert F.round_trip(completed) == completed

      if action == Chat.CreateThread,
        do: assert(completed.data["result"] == %{"id" => "7", "room_id" => "123", "name" => "Support"})

      if action == Chat.OpenDm, do: assert(completed.data["result"] == %{"id" => "123", "kind" => "direct"})
    end

    for raw <- [%{"id" => 123, "type" => "group"}, %{"id" => 456, "type" => "private"}] do
      assert {:error, %Chat.Error{code: :not_found}} =
               F.run(Chat.OpenDm, client, %{"user_id" => "123"}, contract_response: {:ok, raw})

      assert_receive {:telegram_contract_wire, _, "getChat", _, _, _}
    end

    assert :ok = Chat.AdapterTestKit.Assertions.assert_unsupported_operations(client)

    for key <- [:reply_markup, :parse_mode, :format, :thread_id, :reply_to_id] do
      assert {:error, %Chat.Error{signal: failed}} =
               F.run(Chat.SendMessage, client, %{"room_id" => "123", "text" => "Hello"}, [{key, "legacy"}])

      assert failed.data["outcome"] == "not_attempted"
    end

    refute_receive {:telegram_contract_wire, _, _, _, _, _}
  end

  @tag obligation: "jido_chat_telegram.adapter.I3"
  test "core files and all provider media share portable source and canonical reference behavior" do
    for id <- ["alpha", "beta"] do
      client = F.client(id)

      sources = [
        {%{"client_id" => id, "kind" => "file", "id" => "/tmp/contract-upload.bin"},
         {:file, "/tmp/contract-upload.bin"}},
        {%{"client_id" => id, "kind" => "url", "id" => "https://example.com/file.bin"}, "https://example.com/file.bin"},
        {%{"client_id" => id, "kind" => "media", "id" => "telegram://file/input"}, "input"},
        {%{"content_base64" => Base.encode64(<<0, 255, 1, 2>>), "filename" => "bytes.bin"},
         {:file_content, <<0, 255, 1, 2>>, "bytes.bin"}}
      ]

      for {action, kind, method, field} <- [
            {Chat.SendFile, "image", "sendPhoto", "photo"},
            {Chat.SendFile, "file", "sendDocument", "document"},
            {Telegram.SendPhoto, nil, "sendPhoto", "photo"},
            {Telegram.SendDocument, nil, "sendDocument", "document"},
            {Telegram.SendSticker, nil, "sendSticker", "sticker"},
            {Telegram.SendAnimation, nil, "sendAnimation", "animation"},
            {Telegram.SendVideoNote, nil, "sendVideoNote", "video_note"}
          ],
          {source, expected} <- sources do
        fields = %{"room_id" => "123", "source" => source}
        fields = if kind, do: Map.put(fields, "media_kind", kind), else: fields
        assert {:ok, %{signal: completed}} = F.run(action, client, fields)
        assert_receive {:telegram_contract_wire, _, ^method, payload, _, _}
        assert payload[field] == expected
        result = completed.data["result"]
        reference = if kind, do: hd(result["media"])["resource_ref"], else: result["resource_ref"]
        assert reference == %{"client_id" => id, "kind" => "media", "id" => "telegram://file/file-1"}
        assert result["id"] == "42"
        assert F.round_trip(completed) == completed
      end
    end

    refute_receive {:telegram_contract_wire, _, _, _, _, _}
  end

  @tag obligation: "jido_chat_telegram.adapter.I3"
  test "GetFile and DownloadFile agree and unsafe metadata stops before any download" do
    client = F.client()
    reference = %{"client_id" => client.id, "kind" => "media", "id" => "telegram://file/file-1"}
    assert {:ok, %{signal: file}} = F.run(Telegram.GetFile, client)
    assert file.data["result"]["resource_ref"] == reference
    assert file.data["result"]["file_path"] == "documents/report.txt"
    assert_receive {:telegram_contract_wire, _, "getFile", %{"file_id" => "file-1"}, _, _}
    assert {:ok, downloaded} = Chat.download_file(client, reference)
    assert Base.decode64!(downloaded.data["result"]["content_base64"]) == <<0, 255, 1, 2>>
    assert_receive {:telegram_contract_wire, _, "getFile", %{"file_id" => "file-1"}, _, _}
    assert_receive {:telegram_contract_wire, _, "downloadFile", %{"file_path" => "documents/report.txt"}, _, _}
    assert F.round_trip(downloaded) == downloaded

    for path <- [nil, "", "../secret", "/absolute", "a//b", "https://example.com/file", "a?token=secret"] do
      response = {:ok, %{"file_id" => "file-1", "file_path" => path}}

      assert {:error, %Chat.Error{code: :invalid_provider_result}} =
               Chat.download_file(client, reference, options: [contract_response: response])

      assert_receive {:telegram_contract_wire, _, "getFile", _, _, _}
      refute_receive {:telegram_contract_wire, _, "downloadFile", _, _, _}
    end

    refute_receive {:telegram_contract_wire, _, _, _, _, _}
  end

  @tag obligation: "jido_chat_telegram.adapter.I4"
  test "all ten incoming event types retain order, item identity, safe projections, and client scope" do
    inputs = Enum.map(F.incoming(), & &1["update"])

    expected =
      Enum.flat_map(F.incoming(), fn row ->
        Enum.map(row["facts"], &Map.put(&1, "update_id", row["update"]["update_id"]))
      end)

    for id <- ["alpha", "beta"] do
      client = F.client(id)
      assert {:ok, delivery} = Chat.normalize(client, inputs)
      assert {:ok, repeated} = Chat.normalize(client, inputs)
      assert delivery.id == repeated.id
      assert Enum.map(delivery.signals, &F.projection/1) == Enum.map(repeated.signals, &F.projection/1)

      assert Enum.sort(Enum.uniq(Enum.map(delivery.signals, & &1.type))) ==
               Telegram.event_definitions() |> Enum.map(& &1.type()) |> Enum.sort()

      assert length(delivery.signals) == length(expected)

      for {signal, fixture} <- Enum.zip(delivery.signals, expected) do
        assert signal.type == fixture["type"]
        assert %Jido.Trace{} = Jido.Signal.Context.get_trace(signal)
        assert signal.source == client.source
        assert signal.data["delivery_id"] == delivery.id
        assert signal.data["item_id"] == "telegram:update:#{fixture["update_id"]}:#{fixture["item_suffix"]}"
        assert Map.take(signal.data, Map.keys(fixture["fields"])) == fixture["fields"]

        if signal.data["room_id"],
          do: assert(signal.subject == Chat.Signal.Identity.conversation_subject(id, signal.data["room_id"]))

        assert F.round_trip(signal, Chat.catalog(client)) == signal
      end

      first = hd(delivery.signals)
      assert first.data["sender"]["id"] == "42"
      assert first.data["reply_context"]["sender"]["id"] == "11"

      assert hd(first.data["media"])["resource_ref"] == %{
               "client_id" => id,
               "kind" => "media",
               "id" => "telegram://file/document-1"
             }

      assert {:ok, empty} = Chat.normalize(client, [])
      assert empty.signals == []

      assert {:ok, invalid_item} =
               Chat.normalize(client, [hd(inputs), %{"update_id" => 110, "message" => %{}}, hd(inputs)])

      assert Enum.at(invalid_item.signals, 1).data["code"] == "invalid_item"
      assert Enum.at(invalid_item.signals, 1).data["item_index"] == 1
      assert {:error, %Chat.Errors.Contract{}} = Chat.normalize(client, :invalid)
    end

    refute_receive {:telegram_contract_wire, _, _, _, _, _}
  end

  @tag obligation: "jido_chat_telegram.adapter.I5"
  test "pulling preserves normalized facts and only returns host-owned next offsets" do
    client = F.client()
    updates = F.incoming() |> Enum.reverse() |> Enum.map(& &1["update"])
    assert {:ok, direct} = Chat.normalize(client, updates)

    assert {:ok, %{signal: pulled}} =
             F.run(Telegram.FetchUpdates, client, %{"offset" => 100}, contract_response: {:ok, updates})

    assert_receive {:telegram_contract_wire, _, "getUpdates",
                    %{"offset" => 100, "limit" => 10, "timeout" => 0, "allowed_updates" => ["message"]}, _, _}

    result = pulled.data["result"]
    assert result["next_offset"] == 110
    assert result["delivery_id"] == direct.id

    decoded =
      Enum.map(result["signals"], fn wire ->
        assert {:ok, signal} = Jido.Signal.Catalog.decode(Chat.catalog(client), wire)
        signal
      end)

    assert Enum.map(decoded, &F.projection/1) == Enum.map(direct.signals, &F.projection/1)

    for fields <- [%{"offset" => 100}, %{}] do
      request =
        Telegram.Signal.FetchUpdates.new!(Map.merge(%{"client_id" => client.id, "request_id" => "empty"}, fields))

      assert {:ok, empty} = Chat.execute(client, request)
      assert empty.data["result"]["next_offset"] == fields["offset"]
      assert empty.data["result"]["signals"] == []
      assert_receive {:telegram_contract_wire, _, "getUpdates", ^fields, _, _}
    end

    single = hd(updates)
    assert {:ok, webhook} = Chat.normalize(client, single)
    assert {:ok, batch} = Chat.normalize(client, [single])
    refute webhook.id == batch.id
    assert hd(webhook.signals).data["item_id"] == hd(batch.signals).data["item_id"]
    refute_receive {:telegram_contract_wire, _, _, _, _, _}
  end

  @tag obligation: "jido_chat_telegram.adapter.I6"
  test "stream mode selection consumes one source, closes it, and flushes exact final text" do
    for {room, config, options, mode} <- [
          {"123", [], [], :draft},
          {"-123", [], [], :edit},
          {"@channel", [], [], :edit},
          {"123", [stream_delivery: :edit], [], :edit},
          {"123", [stream_delivery: :edit], [stream_delivery: :draft], :draft}
        ] do
      caller = self()

      source =
        Stream.resource(
          fn ->
            send(caller, :opened)
            ["one", " two"]
          end,
          fn
            [] ->
              {:halt, []}

            [head | tail] ->
              send(caller, {:pulled, head})
              {[head], tail}
          end,
          fn _ -> send(caller, :closed) end
        )

      assert {:ok, completed} =
               Chat.stream_text(F.client("alpha", config), room, source, update_interval_ms: 60_000, options: options)

      assert completed.data["result"]["text"] == "one two"
      assert completed.data["result"]["id"] == "42"
      assert_receive :opened
      assert_receive {:pulled, "one"}
      assert_receive {:pulled, " two"}
      assert_receive :closed
      refute_receive :opened
      first = if mode == :draft, do: "sendMessageDraft", else: "sendMessage"
      last = if mode == :draft, do: "sendMessage", else: "editMessageText"
      assert_receive {:telegram_contract_wire, _, first_method, %{"text" => "one"}, _, _}
      assert first_method == first
      assert_receive {:telegram_contract_wire, _, last_method, %{"text" => "one two"} = payload, _, _}
      assert last_method == last
      if mode == :edit, do: assert(payload["message_id"] == "42")
      assert F.round_trip(completed) == completed
      refute_receive {:telegram_contract_wire, _, _, _, _, _}
    end
  end

  @tag obligation: "jido_chat_telegram.adapter.I6"
  test "stream rejection stops reads and does not retry or change delivery mode" do
    caller = self()

    source =
      Stream.map(["first", "second"], fn value ->
        send(caller, {:read, value})
        value
      end)

    error = %ExGram.Error{
      code: :response_status_not_match,
      message: ~s({"error_code":429,"parameters":{"retry_after":2}})
    }

    assert {:error, %Chat.Error{code: :rate_limited, signal: failed}} =
             Chat.stream_text(F.client(), "123", source, options: [contract_response: {:error, error}])

    assert failed.data["outcome"] == "unknown"
    assert failed.data["retry_after_ms"] == 2000
    assert_receive {:read, "first"}
    refute_receive {:read, "second"}
    assert_receive {:telegram_contract_wire, _, "sendMessageDraft", _, _, _}
    refute_receive {:telegram_contract_wire, _, _, _, _, _}

    for {room, mode} <- [{"-123", :draft}, {"123", :invalid}] do
      assert {:error, %Chat.Error{signal: failed}} =
               Chat.stream_text(F.client(), room, source, options: [stream_delivery: mode])

      assert failed.data["outcome"] == "not_attempted"
    end

    refute_receive {:read, _}
    refute_receive {:telegram_contract_wire, _, _, _, _, _}
  end
end
