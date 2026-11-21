defmodule Jido.Chat.Telegram.Transport.ExGramBoundaryTest do
  use ExUnit.Case, async: true
  alias ExGram.Model.{InputRichMessage, ReactionTypeCustomEmoji, ReactionTypeEmoji, ReactionTypePaid, ReplyParameters}
  alias Jido.Chat.Telegram.TestHTTP
  alias Jido.Chat.Telegram.Transport.ExGramClient

  defmodule CurrentAPI do
    def get_me(opts), do: {:ok, opts}
    def send_message(chat, text, opts), do: {:ok, {chat, text, opts}}
    def send_rich_message(chat, rich, opts), do: {:ok, {chat, rich, opts}}
    def edit_message_text(opts), do: {:ok, opts}
    def send_sticker(chat, media, opts), do: {:ok, {chat, media, opts}}
    def send_animation(chat, media, opts), do: {:ok, {chat, media, opts}}
    def send_video_note(chat, media, opts), do: {:ok, {chat, media, opts}}
    def set_message_reaction(chat, id, reaction, opts), do: {:ok, {chat, id, reaction, opts}}
    def create_forum_topic(chat, name, opts), do: {:ok, {chat, name, opts}}
  end

  defmodule OlderAPI do
    def get_updates, do: {:ok, []}
    def set_webhook(url), do: {:ok, url}
    def get_webhook_info, do: {:ok, %{url: ""}}
    def delete_webhook, do: {:ok, true}
    def create_forum_topic(chat, opts), do: {:ok, {chat, opts}}
    def request(verb, path, body), do: {:ok, {verb, path, body}}
  end

  defmodule MissingAPI do
  end

  test "media methods preserve upload tuples and provider options" do
    for {method, key} <- [{"sendSticker", "sticker"}, {"sendAnimation", "animation"}, {"sendVideoNote", "video_note"}] do
      upload = {:file_content, "bytes", "media.bin"}

      assert {:ok, {"room", ^upload, opts}} =
               ExGramClient.call(
                 "token",
                 method,
                 %{"chat_id" => "room", key => upload, "message_thread_id" => "12", "disable_notification" => true},
                 ex_gram_module: CurrentAPI
               )

      assert opts[:message_thread_id] == 12
      assert opts[:disable_notification]
      assert opts[:token] == "token"
    end

    assert {:ok, opts} = ExGramClient.call("token", "getMe", %{}, ex_gram_module: CurrentAPI)
    assert opts[:token] == "token"
  end

  test "rich messages use typed content and preserve typed or mapped reply parameters" do
    for reply <- [%ReplyParameters{message_id: 9}, %{"message_id" => "9"}, %{message_id: 9}] do
      assert {:ok, {1, rich, opts}} =
               ExGramClient.call(
                 "token",
                 "sendRichMessage",
                 %{
                   "chat_id" => 1,
                   "rich_message" => %{
                     "markdown" => "**Hello**",
                     :html => "<b>Hello</b>",
                     "is_rtl" => true,
                     "skip_entity_detection" => true,
                     "unknown" => "discard"
                   },
                   "reply_parameters" => reply,
                   "unknown" => "discard"
                 },
                 ex_gram_module: CurrentAPI
               )

      assert rich == %InputRichMessage{
               markdown: "**Hello**",
               html: "<b>Hello</b>",
               is_rtl: true,
               skip_entity_detection: true
             }

      assert opts[:reply_parameters] == %ReplyParameters{message_id: 9}
      refute Keyword.has_key?(opts, :unknown)
    end

    rich = %InputRichMessage{html: "<b>Changed</b>"}

    assert {:ok, opts} =
             ExGramClient.call(
               "token",
               "editMessageText",
               %{
                 chat_id: 1,
                 message_id: "12",
                 rich_message: rich
               },
               ex_gram_module: CurrentAPI
             )

    assert opts[:rich_message] == rich
    assert opts[:message_id] == 12
    refute Keyword.has_key?(opts, :text)
  end

  test "reaction variants convert to provider structs without changing identifiers" do
    reactions = [
      %{"type" => "emoji", "emoji" => "👍"},
      %{type: "emoji", emoji: "👋"},
      %{"type" => "custom_emoji", "custom_emoji_id" => "custom-1"},
      %{type: "custom_emoji", custom_emoji_id: "custom-2"},
      %{"type" => "paid"},
      %{type: "paid"},
      %ReactionTypeEmoji{type: "emoji", emoji: "🎉"}
    ]

    assert {:ok, {-42, 7, converted, opts}} =
             ExGramClient.call(
               "token",
               "setMessageReaction",
               %{"chat_id" => "-42", "message_id" => "7", "reaction" => reactions},
               ex_gram_module: CurrentAPI
             )

    assert converted == [
             %ReactionTypeEmoji{type: "emoji", emoji: "👍"},
             %ReactionTypeEmoji{type: "emoji", emoji: "👋"},
             %ReactionTypeCustomEmoji{type: "custom_emoji", custom_emoji_id: "custom-1"},
             %ReactionTypeCustomEmoji{type: "custom_emoji", custom_emoji_id: "custom-2"},
             %ReactionTypePaid{type: "paid"},
             %ReactionTypePaid{type: "paid"},
             List.last(reactions)
           ]

    assert opts[:token] == "token"

    assert {:ok, {"@channel", "opaque", :unchanged, _}} =
             ExGramClient.call(
               "token",
               "setMessageReaction",
               %{chat_id: "@channel", message_id: "opaque", reaction: :unchanged},
               ex_gram_module: CurrentAPI
             )
  end

  test "forum topic creation supports both ExGram method signatures" do
    payload = %{"chat_id" => -42, "name" => "Support"}

    assert {:ok, {-42, "Support", opts}} =
             ExGramClient.call("token", "createForumTopic", payload, ex_gram_module: CurrentAPI)

    assert opts[:token] == "token"
    assert {:ok, {-42, opts}} = ExGramClient.call("token", "createForumTopic", payload, ex_gram_module: OlderAPI)
    assert opts[:name] == "Support"
    assert opts[:token] == "token"
  end

  test "older provider signatures and three-argument HTTP adapters remain usable" do
    opts = [ex_gram_module: OlderAPI]
    assert {:ok, []} = ExGramClient.call("token", "getUpdates", %{}, opts)

    assert {:ok, "https://example.test/hook"} =
             ExGramClient.call("token", "setWebhook", %{"url" => "https://example.test/hook"}, opts)

    assert {:ok, %{url: ""}} = ExGramClient.call("token", "getWebhookInfo", %{}, opts)
    assert {:ok, true} = ExGramClient.call("token", "deleteWebhook", %{}, opts)

    assert {:ok, {:post, "/bottoken/sendMessageDraft", %{text: "hi"}}} =
             ExGramClient.call("token", "sendMessageDraft", %{"text" => "hi"}, ex_gram_adapter: OlderAPI)
  end

  test "missing provider methods and adapters return explicit errors" do
    for {method, payload} <- [
          {"getUpdates", %{}},
          {"setWebhook", %{"url" => "url"}},
          {"getWebhookInfo", %{}},
          {"deleteWebhook", %{}}
        ] do
      assert {:error, {:unsupported_method, ^method}} =
               ExGramClient.call("token", method, payload, ex_gram_module: MissingAPI)
    end

    for {method, payload} <- [
          {"setMessageReaction", %{"chat_id" => 1, "message_id" => 2}},
          {"createForumTopic", %{"chat_id" => 1, "name" => "test"}}
        ] do
      assert {:error, :unsupported_method} = ExGramClient.call("token", method, payload, ex_gram_module: MissingAPI)
    end

    for adapter <- [MissingAPI, NonexistentTelegramAdapter] do
      assert {:error, :unsupported_adapter} =
               ExGramClient.call("token", "sendMessageDraft", %{}, ex_gram_adapter: adapter)
    end
  end

  test "adapter configuration accepts string maps and top-level values take priority" do
    nested = %{
      "url" => "old",
      "base_url" => "base",
      "connect_timeout" => 10,
      "connect_options" => [timeout: 20],
      "pool_timeout" => 30,
      "receive_timeout" => 40,
      "finch" => Req.Finch,
      "debug" => false,
      "check_params" => false,
      "unknown" => :ignored
    }

    assert {:ok, {1, "hi", opts}} =
             ExGramClient.call("token", "sendMessage", %{chat_id: 1, text: "hi"},
               ex_gram_module: CurrentAPI,
               adapter_opts: nested,
               url: "new",
               debug: true,
               check_params: true
             )

    assert opts[:debug]
    assert opts[:check_params]

    assert Map.new(opts[:adapter_opts]) ==
             nested
             |> Map.delete("unknown")
             |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
             |> Map.put(:url, "new")

    for invalid <- [nil, [nil, {"unknown", 1}, {:receive_timeout, 123}]] do
      assert {:ok, {1, "hi", opts}} =
               ExGramClient.call("token", "sendMessage", %{chat_id: 1, text: "hi"},
                 ex_gram_module: CurrentAPI,
                 adapter_opts: invalid
               )

      assert opts[:adapter_opts] in [nil, [receive_timeout: 123]]
    end
  end

  test "download returns exact bytes and uses the Bot API file endpoint" do
    bytes = <<0, 255, 1, 2>>

    {result, wire} =
      TestHTTP.serve(200, bytes, fn url ->
        ExGramClient.call("fixture", "downloadFile", %{"file_path" => "documents/a.bin"}, url: url <> "/")
      end)

    assert result == {:ok, bytes}
    assert wire =~ "GET /file/botfixture/documents/a.bin HTTP/1.1"

    {result, _} =
      TestHTTP.serve(404, "missing", fn url ->
        ExGramClient.call("fixture", "downloadFile", %{"file_path" => "a"}, base_url: url)
      end)

    assert result == {:error, :download_failed}

    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)

    assert {:error, %Req.TransportError{reason: :econnrefused}} =
             ExGramClient.call("fixture", "downloadFile", %{"file_path" => "a"}, base_url: "http://127.0.0.1:#{port}")
  end
end
