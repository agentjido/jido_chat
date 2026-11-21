defmodule Jido.Chat.Telegram.AdapterSurfaceTest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true
  alias Jido.Chat.Client
  alias Jido.Chat.Telegram, as: Telegram
  alias Telegram.Adapter

  defmodule Transport do
    def call(token, method, payload, opts) do
      send(opts[:observer], {:wire, method, payload, token})

      case Keyword.get(opts, :response, :default) do
        :default -> response(method, payload)
        fun when is_function(fun, 2) -> fun.(method, payload)
        value -> value
      end
    end

    defp response(method, payload) when method in ["sendMessage", "sendRichMessage", "editMessageText"] do
      {:ok,
       %{
         "message_id" => 42,
         "chat" => %{"id" => payload["chat_id"]},
         "text" => payload["text"] || "rich",
         "message_thread_id" => payload["message_thread_id"],
         "reply_to_message" => %{"message_id" => get_in(payload, ["reply_parameters", "message_id"])}
       }}
    end

    defp response(method, payload) when method in ["sendPhoto", "sendDocument"] do
      field = if method == "sendPhoto", do: "photo", else: "document"
      media = %{"file_id" => "file-1"}

      {:ok,
       %{
         "message_id" => 42,
         "chat" => %{"id" => payload["chat_id"]},
         field => if(field == "photo", do: [media], else: media)
       }}
    end

    defp response("getChat", payload),
      do: {:ok, %ExGram.Model.ChatFullInfo{id: payload["chat_id"], type: "private", first_name: "Alice"}}

    defp response("createForumTopic", _), do: {:ok, %{"message_thread_id" => 7, "name" => "Topic"}}

    defp response("getFile", payload),
      do: {:ok, %{"file_id" => payload["file_id"], "file_path" => "documents/test.json", "file_size" => 2}}

    defp response("downloadFile", _), do: {:ok, "{}"}

    defp response("getWebhookInfo", _),
      do: {:ok, %{"url" => "", "pending_update_count" => 0, "has_custom_certificate" => false}}

    defp response(_, _), do: {:ok, true}
  end

  defp client,
    do:
      Client.new!(Adapter,
        id: "telegram",
        credentials: %{token: "private-token", secret_token: "private-secret"},
        transport: Transport
      )

  defp reference(kind \\ "media", id \\ "telegram://file/file-1"),
    do: %{"client_id" => "telegram", "kind" => kind, "id" => id}

  defp request(action, data),
    do: action.signal_definition().new!(Map.merge(%{"client_id" => "telegram", "request_id" => "request"}, data))

  defp run(action, data, opts \\ []) do
    Jido.Chat.Telegram.ActionHelpers.execute(
      action,
      request(action, data),
      %{client: client(), options: [observer: self()] ++ opts},
      max_attempts: 1
    )
  end

  test "adapter exposes only native operation and normalization callbacks" do
    assert Adapter.channel_type() == :telegram
    assert Adapter.default_transport() == Telegram.Transport.ExGramClient
    assert Adapter.capabilities()[:send_file] == :native
    assert Adapter.capabilities()[:post_ephemeral] == :unsupported

    for {name, arity} <- [
          send_message: 3,
          send_file: 3,
          stream: 3,
          download_file: 2,
          ensure_ingress_subscription: 2,
          list_ingress_subscriptions: 2,
          delete_ingress_subscription: 3
        ] do
      refute function_exported?(Adapter, name, arity)
    end
  end

  test "send, edit, and stream carry format, replies, and thread routing in Signals" do
    for {action, method, text_field} <- [
          {Jido.Chat.SendMessage, "sendMessage", "text"},
          {Jido.Chat.EditMessage, "editMessageText", "text"}
        ],
        format <- ["plain", "markdown", "html"] do
      data = %{"room_id" => "123", "thread_id" => "7", "reply_to_id" => "9", "format" => format}

      data = Map.put(data, "text", "Hello world")

      data = if action == Jido.Chat.EditMessage, do: Map.put(data, "message_id", "42"), else: data
      # EditMessage has no reply target: it changes the original message.
      data = if action == Jido.Chat.EditMessage, do: Map.drop(data, ["reply_to_id", "thread_id"]), else: data
      assert {:ok, %{signal: completed}} = run(action, data)
      expected_method = if action != Jido.Chat.EditMessage and format != "plain", do: "sendRichMessage", else: method
      assert_receive {:wire, ^expected_method, payload, "private-token"}
      if action != Jido.Chat.EditMessage, do: assert(payload["message_thread_id"] == "7")
      if action != Jido.Chat.EditMessage, do: assert(payload["reply_parameters"] == %{"message_id" => "9"})

      if format == "plain",
        do: assert(payload[text_field] == "Hello world"),
        else: assert(payload["rich_message"] == %{format => "Hello world"})

      assert completed.data["result"]["id"] == "42"
    end
  end

  test "keyboards enter through validated request data and an empty keyboard clears buttons" do
    keyboard = %{
      "rows" => [[%{"text" => "Confirm", "value" => "confirm:1"}, %{"text" => "Help", "url" => "https://example.com"}]]
    }

    assert {:ok, _} = run(Jido.Chat.SendMessage, %{"room_id" => "123", "text" => "Choose", "keyboard" => keyboard})
    assert_receive {:wire, "sendMessage", payload, _}

    assert payload["reply_markup"] == %{
             "inline_keyboard" => [
               [
                 %{"text" => "Confirm", "callback_data" => "confirm:1"},
                 %{"text" => "Help", "url" => "https://example.com"}
               ]
             ]
           }

    assert {:ok, _} =
             run(Jido.Chat.EditMessage, %{
               "room_id" => "123",
               "message_id" => "42",
               "text" => "Done",
               "keyboard" => %{"rows" => []}
             })

    assert_receive {:wire, "editMessageText", %{"reply_markup" => %{"inline_keyboard" => []}}, _}
  end

  test "a forged invalid keyboard is rejected before transport I/O" do
    original = request(Jido.Chat.SendMessage, %{"room_id" => "123", "text" => "Choose"})

    invalid = %{
      original
      | data:
          Map.put(original.data, "keyboard", %{
            "rows" => [[%{"text" => "Confirm", "value" => String.duplicate("é", 33)}]]
          })
    }

    assert {:error, _} =
             Jido.Chat.Telegram.ActionHelpers.execute(Jido.Chat.SendMessage, invalid, %{
               client: client(),
               options: [observer: self()]
             })

    refute_receive {:wire, _, _, _}
  end

  test "old content options cannot bypass the Signal schema" do
    for opts <- [[reply_markup: %{}], [parse_mode: "HTML"], [rich_format: :html], [thread_id: "7"]] do
      assert {:error, %Jido.Chat.Error{signal: failed}} =
               run(Jido.Chat.SendMessage, %{"room_id" => "123", "text" => "Hello"}, opts)

      assert failed.data["outcome"] == "not_attempted"
    end

    refute_receive {:wire, _, _, _}
  end

  test "metadata and direct addressing verify rooms with provider reads" do
    assert {:ok, %{signal: completed}} = run(Jido.Chat.FetchMetadata, %{"room_id" => "123"})
    assert completed.data["result"] == %{"id" => "123", "name" => "Alice", "kind" => "direct"}
    assert_receive {:wire, "getChat", _, _}
    assert {:ok, %{signal: direct}} = run(Jido.Chat.OpenDm, %{"user_id" => "123"})
    assert direct.data["result"] == %{"id" => "123", "kind" => "direct"}
    assert_receive {:wire, "getChat", %{"chat_id" => "123"}, _}
    refute_receive {:wire, _, _, _}
  end

  test "delete, typing, reactions, and topics use native core Actions" do
    for {action, data, method} <- [
          {Jido.Chat.DeleteMessage, %{"message_id" => "42"}, "deleteMessage"},
          {Jido.Chat.StartTyping, %{"thread_id" => "7"}, "sendChatAction"},
          {Jido.Chat.AddReaction, %{"message_id" => "42", "reaction" => "👍"}, "setMessageReaction"},
          {Jido.Chat.RemoveReaction, %{"message_id" => "42", "reaction" => "👍"}, "setMessageReaction"},
          {Jido.Chat.CreateThread, %{"name" => "Topic"}, "createForumTopic"}
        ] do
      assert {:ok, _} = run(action, Map.put(data, "room_id", "123"))
      assert_receive {:wire, ^method, _, _}
    end
  end

  test "CreateThread requires a name and SendMessage addresses the created topic" do
    catalog = Telegram.catalog()

    created =
      Jido.Chat.AdapterTestKit.Assertions.assert_operation_success(
        run(Jido.Chat.CreateThread, %{"room_id" => "123", "name" => "Topic"}),
        catalog
      )

    assert_receive {:wire, "createForumTopic", payload, _}
    assert payload == %{"chat_id" => "123", "name" => "Topic"}
    assert created.type == Jido.Chat.CreateThread.Completed.type()

    sent =
      Jido.Chat.AdapterTestKit.Assertions.assert_operation_success(
        run(Jido.Chat.SendMessage, %{"room_id" => "123", "thread_id" => created.data["result"]["id"], "text" => "Hello"}),
        catalog
      )

    assert_receive {:wire, "sendMessage", %{"message_thread_id" => "7"}, _}
    assert sent.type == Jido.Chat.SendMessage.Completed.type()
    assert :ok = Jido.Chat.AdapterTestKit.Assertions.assert_json_round_trip(sent, catalog)

    assert {:error, _} =
             Jido.Chat.Signal.Policy.new(Jido.Chat.Signal.CreateThread, %{
               "client_id" => "telegram",
               "request_id" => "r",
               "room_id" => "123",
               "message_id" => "unused"
             })

    refute_receive {:wire, _, _, _}
  end

  test "the shared test kit handles core and Telegram extension failures in one catalog" do
    alias Jido.Chat.AdapterTestKit.Assertions
    catalog = Telegram.catalog()

    for action <- [Jido.Chat.SendMessage, Telegram.GetMe] do
      data = if action == Jido.Chat.SendMessage, do: %{"room_id" => "123", "text" => "Hello"}, else: %{}
      result = run(action, data, response: {:error, {:rejected, :test}})
      failed = Assertions.assert_operation_failure(result, catalog)
      assert failed.type == action.signal_definition().type() <> ".failed"
      assert :ok = Assertions.assert_json_round_trip(failed, catalog)
      assert_receive {:wire, _, _, _}
    end

    completed =
      Assertions.assert_operation_success(
        run(Telegram.GetMe, %{}, response: {:ok, %{"id" => 1, "is_bot" => true}}),
        catalog
      )

    assert completed.type == Telegram.GetMe.Completed.type()
    assert :ok = Assertions.assert_json_round_trip(completed, catalog)
  end

  test "unsupported operations fail before transport I/O" do
    req = Jido.Chat.AdapterTestKit.Factories.operation_request(client(), :post_ephemeral)

    assert {:error, %Jido.Chat.Error{code: :unsupported}} =
             Jido.Chat.Telegram.ActionHelpers.execute(Jido.Chat.PostEphemeral, req, %{client: client()})

    refute_receive {:wire, _, _, _}
  end

  test "core SendFile and Telegram uploads use the same source and result validation" do
    for {action, kind, method, key} <- [
          {Jido.Chat.SendFile, "file", "sendDocument", "document"},
          {Jido.Chat.SendFile, "image", "sendPhoto", "photo"},
          {Telegram.SendDocument, nil, "sendDocument", "document"},
          {Telegram.SendPhoto, nil, "sendPhoto", "photo"}
        ],
        {source, wire} <- [
          {reference("file", "/tmp/file.txt"), {:file, "/tmp/file.txt"}},
          {reference("url", "https://example.com/a.txt"), "https://example.com/a.txt"},
          {reference(), "file-1"},
          {%{"content_base64" => Base.encode64("bytes"), "filename" => "a.txt"}, {:file_content, "bytes", "a.txt"}}
        ] do
      data = %{
        "room_id" => "123",
        "source" => source,
        "caption" => "Caption",
        "reply_to_id" => "9",
        "thread_id" => "7",
        "format" => "html"
      }

      data = if kind, do: Map.put(data, "media_kind", kind), else: data
      assert {:ok, %{signal: completed}} = run(action, data)
      assert_receive {:wire, ^method, payload, _}
      assert payload[key] == wire
      assert payload["caption"] == "Caption"
      assert payload["parse_mode"] == "HTML"
      assert payload["reply_parameters"] == %{"message_id" => "9"}
      assert payload["message_thread_id"] == "7"
      result = completed.data["result"]
      ref = if kind, do: hd(result["media"])["resource_ref"], else: result["resource_ref"]
      assert ref == reference()
    end
  end

  test "uploads never invent a message ID or accept a missing file ID" do
    for action <- [Jido.Chat.SendFile, Telegram.SendDocument],
        raw <- [
          %{"document" => %{"file_id" => "f"}},
          %{"message_id" => 42, "chat" => %{"id" => 123}},
          %{"message_id" => 42, "chat" => %{"id" => 456}, "document" => %{"file_id" => "f"}}
        ] do
      assert {:error, %Jido.Chat.Error{code: :invalid_provider_result}} =
               run(action, %{"room_id" => "123", "source" => reference()}, response: {:ok, raw})

      assert_receive {:wire, "sendDocument", _, _}
    end
  end

  test "GetFile and DownloadFile share file resolution and preserve exact JSON bytes" do
    assert {:ok, %{signal: info}} = run(Telegram.GetFile, %{"resource_ref" => reference()})
    assert info.data["result"]["file_path"] == "documents/test.json"
    assert_receive {:wire, "getFile", %{"file_id" => "file-1"}, _}
    assert {:ok, %{signal: downloaded}} = run(Jido.Chat.DownloadFile, %{"resource_ref" => reference()})
    assert downloaded.data["result"]["content_base64"] == Base.encode64("{}")
    assert_receive {:wire, "getFile", %{"file_id" => "file-1"}, _}
    assert_receive {:wire, "downloadFile", %{"file_path" => "documents/test.json"}, _}
    assert {:ok, json} = Jido.Signal.Codec.serialize(downloaded)
    refute json =~ "private-token"
    refute json =~ "/bot"
  end

  test "malformed file metadata cannot trigger a download" do
    for path <- [nil, "", "../secret", "https://example.com/file", "/etc/passwd"] do
      assert {:error, %Jido.Chat.Error{code: :invalid_provider_result}} =
               run(Jido.Chat.DownloadFile, %{"resource_ref" => reference()},
                 response: {:ok, %{"file_id" => "f", "file_path" => path}}
               )

      assert_receive {:wire, "getFile", _, _}
      refute_receive {:wire, "downloadFile", _, _}
    end
  end

  test "download errors do not leak token URLs or create a completed Signal" do
    response = fn
      "getFile", _ -> {:ok, %{"file_id" => "file-1", "file_path" => "documents/test.json"}}
      "downloadFile", _ -> {:error, "https://api.telegram.org/file/botprivate-token/path"}
    end

    assert {:error, %Jido.Chat.Error{signal: failed}} =
             run(Jido.Chat.DownloadFile, %{"resource_ref" => reference()}, response: response)

    refute inspect(failed) =~ "private-token"
  end

  test "webhook Actions make one explicit call and keep the secret in private context" do
    assert {:ok, %{signal: set}} =
             run(Telegram.SetWebhook, %{
               "url" => "https://example.com/webhook",
               "allowed_updates" => ["message"],
               "drop_pending_updates" => false
             })

    assert set.data["result"]["acknowledged"]

    assert_receive {:wire, "setWebhook",
                    %{
                      "url" => "https://example.com/webhook",
                      "secret_token" => "private-secret",
                      "drop_pending_updates" => false
                    }, _}

    assert {:ok, %{signal: info}} = run(Telegram.GetWebhookInfo, %{})
    assert info.data["result"]["pending_update_count"] == 0
    assert_receive {:wire, "getWebhookInfo", %{}, _}
    assert {:ok, _} = run(Telegram.DeleteWebhook, %{"drop_pending_updates" => false})
    assert_receive {:wire, "deleteWebhook", %{"drop_pending_updates" => false}, _}
    assert {:ok, json} = Jido.Signal.Codec.serialize(set)
    refute json =~ "private-secret"
    refute_receive {:wire, _, _, _}
  end

  test "webhook verification is pure and requires a configured secret" do
    assert :ok = Telegram.Webhook.verify(client(), [{"X-Telegram-Bot-Api-Secret-Token", "private-secret"}])
    assert {:error, :invalid_webhook_secret} = Telegram.Webhook.verify(client(), %{})

    assert {:error, :invalid_webhook_secret} =
             Telegram.Webhook.verify(client(), %{"x-telegram-bot-api-secret-token" => "other"})

    assert {:error, :missing_webhook_secret} = Telegram.Webhook.verify(%{client() | credentials: %{}}, %{})
    refute_receive {:wire, _, _, _}
  end
end
