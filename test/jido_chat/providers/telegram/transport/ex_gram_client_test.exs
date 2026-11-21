defmodule Jido.Chat.Telegram.Transport.ExGramClientTest do
  use ExUnit.Case, async: true

  alias ExGram.Model.ReactionTypeEmoji
  alias Jido.Chat.Telegram.ExGramAdapter
  alias Jido.Chat.Telegram.Transport.ExGramClient

  defmodule MockExGram do
    def send_message(chat_id, text, opts) do
      send(self(), {:send_message, chat_id, text, opts})
      {:ok, %{message_id: 99, chat: %{id: chat_id}, date: 1_706_745_600}}
    end

    def send_poll(chat_id, question, options, opts) do
      send(self(), {:send_poll, chat_id, question, options, opts})
      {:ok, %{message_id: 42}}
    end

    def edit_message_text(text, opts) do
      send(self(), {:edit_message_text, text, opts})
      {:ok, true}
    end

    def delete_message(chat_id, message_id, opts) do
      send(self(), {:delete_message, chat_id, message_id, opts})
      {:ok, true}
    end

    def send_chat_action(chat_id, action, opts) do
      send(self(), {:send_chat_action, chat_id, action, opts})
      {:ok, true}
    end

    def get_chat(chat_id, opts) do
      send(self(), {:get_chat, chat_id, opts})
      {:ok, %{id: chat_id, type: "private", first_name: "Alice"}}
    end

    def get_file(file_id, opts) do
      send(self(), {:get_file, file_id, opts})
      {:ok, %{file_id: file_id, file_unique_id: "unique-1", file_path: "documents/file.txt"}}
    end

    def set_message_reaction(chat_id, message_id, opts) do
      send(self(), {:set_message_reaction, chat_id, message_id, opts})
      {:ok, true}
    end

    def send_photo(chat_id, photo, opts) do
      send(self(), {:send_photo, chat_id, photo, opts})
      {:ok, %{message_id: 100, chat: %{id: chat_id}, photo: [%{file_id: "photo-file"}]}}
    end

    def send_document(chat_id, document, opts) do
      send(self(), {:send_document, chat_id, document, opts})
      {:ok, %{message_id: 101, chat: %{id: chat_id}, document: %{file_id: "doc-file"}}}
    end

    def answer_callback_query(callback_query_id, opts) do
      send(self(), {:answer_callback_query, callback_query_id, opts})
      {:ok, true}
    end

    def get_updates(opts) do
      send(self(), {:get_updates, opts})
      {:ok, [%{"update_id" => 11, "message" => %{"message_id" => 1}}]}
    end

    def set_webhook(url, opts) do
      send(self(), {:set_webhook, url, opts})
      {:ok, true}
    end

    def get_webhook_info(opts) do
      send(self(), {:get_webhook_info, opts})
      {:ok, %{url: "https://example.test/webhooks/telegram"}}
    end

    def delete_webhook(opts) do
      send(self(), {:delete_webhook, opts})
      {:ok, true}
    end
  end

  test "portable keyboard maps become ExGram models only at the transport boundary" do
    payload = %{
      "chat_id" => "123",
      "text" => "Choose",
      "reply_markup" => %{
        "inline_keyboard" => [
          [%{"text" => "Confirm", "callback_data" => "confirm:1"}, %{"text" => "Help", "url" => "https://example.com"}]
        ]
      }
    }

    assert {:ok, _} = ExGramClient.call("private-token", "sendMessage", payload, ex_gram_module: MockExGram)
    assert_receive {:send_message, "123", "Choose", opts}
    assert %ExGram.Model.InlineKeyboardMarkup{inline_keyboard: [[confirm, help]]} = opts[:reply_markup]
    assert %ExGram.Model.InlineKeyboardButton{callback_data: "confirm:1"} = confirm
    assert %ExGram.Model.InlineKeyboardButton{url: "https://example.com"} = help

    encoded =
      ExGram.Adapter.filter_map(%{reply_markup: opts[:reply_markup]}) |> ExGram.Adapter.encode() |> Jason.decode!()

    assert get_in(encoded, ["reply_markup", "inline_keyboard", Access.at(0), Access.at(0), "callback_data"]) ==
             "confirm:1"
  end

  defmodule MockHttpAdapter do
    @behaviour ExGram.Adapter

    @impl true
    def request(verb, path, body, opts) do
      send(self(), {:http_request, verb, path, body, opts})
      {:ok, true}
    end
  end

  test "call/4 dispatches sendMessage via ExGram" do
    assert {:ok, %{message_id: 99}} =
             ExGramClient.call(
               "abc",
               "sendMessage",
               %{"chat_id" => 1, "text" => "hi", "parse_mode" => "HTML"},
               ex_gram_module: MockExGram
             )

    assert_received {:send_message, 1, "hi", opts}
    assert Keyword.get(opts, :parse_mode) == "HTML"
    assert Keyword.get(opts, :token) == "abc"
    assert Keyword.get(opts, :adapter) == ExGramAdapter
  end

  test "call/4 dispatches sendPoll with typed options via ExGram" do
    assert Code.ensure_loaded?(ExGram) and function_exported?(ExGram, :send_poll, 4)

    assert {:ok, %{message_id: 42}} =
             ExGramClient.call(
               "abc",
               "sendPoll",
               %{
                 "chat_id" => "123",
                 "question" => "Ship today?",
                 "options" => [%{"text" => "Yes"}, %{"text" => "No"}],
                 "message_thread_id" => "7",
                 "is_anonymous" => false
               },
               ex_gram_module: MockExGram
             )

    assert_received {:send_poll, "123", "Ship today?", [%ExGram.Model.InputPollOption{text: "Yes"}, _], opts}
    assert opts[:token] == "abc"
    assert opts[:message_thread_id] == 7
    assert opts[:is_anonymous] == false
  end

  test "plain messages and media use typed reply_parameters instead of the removed reply field" do
    for {method, field} <- [{"sendMessage", "text"}, {"sendPhoto", "photo"}, {"sendDocument", "document"}] do
      assert {:ok, _} =
               ExGramClient.call("abc", method, %{"chat_id" => 1, field => "body", "reply_to_message_id" => "7"},
                 ex_gram_module: MockExGram
               )

      assert_receive {_, 1, "body", opts}
      assert opts[:reply_parameters] == %ExGram.Model.ReplyParameters{message_id: 7}
      refute Keyword.has_key?(opts, :reply_to_message_id)
    end
  end

  test "call/4 forwards url as ExGram adapter opts" do
    assert {:ok, %{message_id: 99}} =
             ExGramClient.call(
               "abc",
               "sendMessage",
               %{"chat_id" => 1, "text" => "hi"},
               ex_gram_module: MockExGram,
               url: "http://localhost:8081"
             )

    assert_received {:send_message, 1, "hi", opts}
    assert Keyword.get(opts, :token) == "abc"
    assert Keyword.get(opts, :adapter) == ExGramAdapter
    assert Keyword.get(opts, :adapter_opts) == [url: "http://localhost:8081"]
  end

  test "call/4 dispatches editMessageText via ExGram" do
    assert {:ok, true} =
             ExGramClient.call(
               "abc",
               "editMessageText",
               %{"chat_id" => 1, "message_id" => 7, "text" => "updated"},
               ex_gram_module: MockExGram
             )

    assert_received {:edit_message_text, "updated", opts}
    assert Keyword.get(opts, :chat_id) == 1
    assert Keyword.get(opts, :message_id) == 7
    assert Keyword.get(opts, :token) == "abc"
    assert Keyword.get(opts, :adapter) == ExGramAdapter
  end

  test "call/4 normalizes numeric string message ids for ExGram" do
    assert {:ok, true} =
             ExGramClient.call(
               "abc",
               "editMessageText",
               %{"chat_id" => 1, "message_id" => "7", "text" => "updated"},
               ex_gram_module: MockExGram
             )

    assert_received {:edit_message_text, "updated", opts}
    assert Keyword.get(opts, :message_id) == 7
  end

  test "call/4 dispatches deleteMessage via ExGram" do
    assert {:ok, true} =
             ExGramClient.call(
               "abc",
               "deleteMessage",
               %{"chat_id" => 1, "message_id" => 7},
               ex_gram_module: MockExGram
             )

    assert_received {:delete_message, 1, 7, opts}
    assert Keyword.get(opts, :token) == "abc"
    assert Keyword.get(opts, :adapter) == ExGramAdapter
  end

  test "call/4 dispatches sendChatAction via ExGram" do
    assert {:ok, true} =
             ExGramClient.call(
               "abc",
               "sendChatAction",
               %{"chat_id" => 1, "action" => "typing", "message_thread_id" => 9},
               ex_gram_module: MockExGram
             )

    assert_received {:send_chat_action, 1, "typing", opts}
    assert Keyword.get(opts, :message_thread_id) == 9
    assert Keyword.get(opts, :token) == "abc"
    assert Keyword.get(opts, :adapter) == ExGramAdapter
  end

  test "call/4 dispatches getChat via ExGram" do
    assert {:ok, %{id: 1}} =
             ExGramClient.call(
               "abc",
               "getChat",
               %{"chat_id" => 1},
               ex_gram_module: MockExGram
             )

    assert_received {:get_chat, 1, opts}
    assert Keyword.get(opts, :token) == "abc"
    assert Keyword.get(opts, :adapter) == ExGramAdapter
  end

  test "call/4 dispatches getFile via ExGram" do
    assert {:ok, %{file_path: "documents/file.txt"}} =
             ExGramClient.call(
               "abc",
               "getFile",
               %{"file_id" => "file-1"},
               ex_gram_module: MockExGram,
               url: "http://localhost:8081"
             )

    assert_received {:get_file, "file-1", opts}
    assert Keyword.get(opts, :token) == "abc"
    assert Keyword.get(opts, :adapter) == ExGramAdapter
    assert Keyword.get(opts, :adapter_opts) == [url: "http://localhost:8081"]
  end

  test "call/4 dispatches getUpdates via ExGram" do
    assert {:ok, [%{"update_id" => 11}]} =
             ExGramClient.call(
               "abc",
               "getUpdates",
               %{"offset" => 10, "timeout" => 25, "allowed_updates" => ["message"]},
               ex_gram_module: MockExGram
             )

    assert_received {:get_updates, opts}
    assert Keyword.get(opts, :offset) == 10
    assert Keyword.get(opts, :timeout) == 25
    assert Keyword.get(opts, :allowed_updates) == ["message"]
    assert Keyword.get(opts, :token) == "abc"
  end

  test "call/4 dispatches setWebhook via ExGram" do
    assert {:ok, true} =
             ExGramClient.call(
               "abc",
               "setWebhook",
               %{
                 "url" => "https://example.test/webhooks/telegram",
                 "allowed_updates" => ["message"],
                 "secret_token" => "secret"
               },
               ex_gram_module: MockExGram
             )

    assert_received {:set_webhook, "https://example.test/webhooks/telegram", opts}
    assert Keyword.get(opts, :allowed_updates) == ["message"]
    assert Keyword.get(opts, :secret_token) == "secret"
    assert Keyword.get(opts, :token) == "abc"
  end

  test "call/4 dispatches getWebhookInfo via ExGram" do
    assert {:ok, %{url: "https://example.test/webhooks/telegram"}} =
             ExGramClient.call("abc", "getWebhookInfo", %{}, ex_gram_module: MockExGram)

    assert_received {:get_webhook_info, opts}
    assert Keyword.get(opts, :token) == "abc"
  end

  test "call/4 dispatches deleteWebhook via ExGram" do
    assert {:ok, true} =
             ExGramClient.call(
               "abc",
               "deleteWebhook",
               %{"drop_pending_updates" => true},
               ex_gram_module: MockExGram
             )

    assert_received {:delete_webhook, opts}
    assert Keyword.get(opts, :drop_pending_updates) == true
    assert Keyword.get(opts, :token) == "abc"
  end

  test "call/4 returns unsupported for unknown methods" do
    assert {:error, {:unsupported_method, "unknownMethod"}} =
             ExGramClient.call("abc", "unknownMethod", %{}, [])
  end

  test "call/4 dispatches sendMessageDraft via the configured HTTP adapter" do
    assert {:ok, true} =
             ExGramClient.call(
               "abc",
               "sendMessageDraft",
               %{
                 "chat_id" => 1,
                 "message_thread_id" => 9,
                 "draft_id" => 77,
                 "text" => "hello",
                 "parse_mode" => "Markdown",
                 "entities" => [%{"type" => "bold", "offset" => 0, "length" => 5}]
               },
               ex_gram_adapter: MockHttpAdapter
             )

    assert_received {:http_request, :post, "/botabc/sendMessageDraft", body, opts}
    assert body.chat_id == 1
    assert body.message_thread_id == 9
    assert body.draft_id == 77
    assert body.text == "hello"
    assert body.parse_mode == "Markdown"
    assert body.entities == [%{"type" => "bold", "offset" => 0, "length" => 5}]
    assert opts == []
  end

  test "call/4 dispatches sendRichMessageDraft via the configured HTTP adapter" do
    assert {:ok, true} =
             ExGramClient.call(
               "abc",
               "sendRichMessageDraft",
               %{
                 "chat_id" => 1,
                 "message_thread_id" => 9,
                 "draft_id" => 77,
                 "rich_message" => %{"markdown" => "| A | B |"}
               },
               ex_gram_adapter: MockHttpAdapter
             )

    assert_received {:http_request, :post, "/botabc/sendRichMessageDraft", body, opts}
    assert body.chat_id == 1
    assert body.message_thread_id == 9
    assert body.draft_id == 77
    assert body.rich_message == %{"markdown" => "| A | B |"}
    assert opts == []
  end

  test "call/4 forwards url to the configured HTTP adapter" do
    assert {:ok, true} =
             ExGramClient.call(
               "abc",
               "sendMessageDraft",
               %{"chat_id" => 1, "draft_id" => 77, "text" => "hello"},
               ex_gram_adapter: MockHttpAdapter,
               url: "http://localhost:8081"
             )

    assert_received {:http_request, :post, "/botabc/sendMessageDraft", _body, opts}
    assert opts == [url: "http://localhost:8081"]
  end

  test "ExGramAdapter.request/4 uses url adapter option as base URL" do
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen_socket)
    parent = self()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listen_socket)
        {:ok, request} = :gen_tcp.recv(socket, 0, 1_000)
        send(parent, {:local_bot_api_request, request})

        body = ~s({"ok":true,"result":{"message_id":123}})

        response = [
          "HTTP/1.1 200 OK\r\n",
          "content-type: application/json\r\n",
          "content-length: #{byte_size(body)}\r\n",
          "\r\n",
          body
        ]

        :ok = :gen_tcp.send(socket, response)
        :ok = :gen_tcp.close(socket)
      end)

    assert {:ok, %{message_id: 123}} =
             ExGramAdapter.request(
               :post,
               "/botabc/sendMessage",
               %{chat_id: 1, text: "hi"},
               url: "http://127.0.0.1:#{port}"
             )

    assert_receive {:local_bot_api_request, request}, 1_000
    assert request =~ "POST /botabc/sendMessage HTTP/1.1"

    Task.await(server, 1_000)
    :gen_tcp.close(listen_socket)
  end

  test "call/4 dispatches setMessageReaction via ExGram when available" do
    assert {:ok, true} =
             ExGramClient.call(
               "abc",
               "setMessageReaction",
               %{
                 "chat_id" => 1,
                 "message_id" => 7,
                 "reaction" => [%{"type" => "emoji", "emoji" => "👍"}],
                 "is_big" => true
               },
               ex_gram_module: MockExGram
             )

    assert_received {:set_message_reaction, 1, 7, opts}
    assert Keyword.get(opts, :reaction) == [%ReactionTypeEmoji{type: "emoji", emoji: "👍"}]
    assert Keyword.get(opts, :is_big) == true
    assert Keyword.get(opts, :token) == "abc"
  end

  test "call/4 dispatches sendPhoto via ExGram" do
    assert {:ok, %{message_id: 100}} =
             ExGramClient.call(
               "abc",
               "sendPhoto",
               %{"chat_id" => 1, "photo" => "photo-id", "caption" => "hello"},
               ex_gram_module: MockExGram
             )

    assert_received {:send_photo, 1, "photo-id", opts}
    assert Keyword.get(opts, :caption) == "hello"
    assert Keyword.get(opts, :token) == "abc"
  end

  test "call/4 dispatches sendDocument via ExGram" do
    assert {:ok, %{message_id: 101}} =
             ExGramClient.call(
               "abc",
               "sendDocument",
               %{"chat_id" => 1, "document" => "doc-id", "caption" => "doc"},
               ex_gram_module: MockExGram
             )

    assert_received {:send_document, 1, "doc-id", opts}
    assert Keyword.get(opts, :caption) == "doc"
    assert Keyword.get(opts, :token) == "abc"
  end

  test "call/4 dispatches answerCallbackQuery via ExGram" do
    assert {:ok, true} =
             ExGramClient.call(
               "abc",
               "answerCallbackQuery",
               %{"callback_query_id" => "cb1", "text" => "done", "show_alert" => true},
               ex_gram_module: MockExGram
             )

    assert_received {:answer_callback_query, "cb1", opts}
    assert Keyword.get(opts, :text) == "done"
    assert Keyword.get(opts, :show_alert) == true
    assert Keyword.get(opts, :token) == "abc"
  end
end
