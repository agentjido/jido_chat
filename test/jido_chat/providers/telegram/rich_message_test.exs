defmodule Jido.Chat.Telegram.RichMessageTest do
  use ExUnit.Case, async: true
  alias ExGram.Model.{InputRichMessage, ReplyParameters}
  alias Jido.Chat.Telegram.Transport.ExGramClient
  @table "| Check | Result |\n| --- | --- |\n| signal | pass |"
  defmodule CapturingExGram do
    def send_rich_message(chat_id, rich_message, opts) do
      send(self(), {:ex_gram_rich, chat_id, rich_message, opts})
      {:ok, %{"message_id" => 7}}
    end

    def send_message(chat_id, text, opts) do
      send(self(), {:ex_gram_send, chat_id, text, opts})
      {:ok, %{"message_id" => 7}}
    end

    # Bot API 10.1 made `text` optional, so ex_gram exposes both arities.
    def edit_message_text(opts) do
      send(self(), {:ex_gram_edit_rich, opts})
      {:ok, %{"message_id" => 7}}
    end

    def edit_message_text(text, opts) do
      send(self(), {:ex_gram_edit_plain, text, opts})
      {:ok, %{"message_id" => 7}}
    end
  end

  describe "ExGramClient" do
    test "builds an InputRichMessage struct for ex_gram" do
      ExGramClient.call(
        "bot-token",
        "sendRichMessage",
        %{"chat_id" => 99, "rich_message" => %{"markdown" => @table}, "disable_notification" => true},
        ex_gram_module: CapturingExGram
      )

      assert_received {:ex_gram_rich, 99, %InputRichMessage{} = rich_message, opts}
      assert rich_message.markdown == @table
      assert rich_message.html == nil
      assert opts[:disable_notification] == true
    end

    test "builds ReplyParameters for a rich reply" do
      ExGramClient.call(
        "bot-token",
        "sendRichMessage",
        %{
          "chat_id" => 99,
          "rich_message" => %{"markdown" => @table},
          "reply_parameters" => %{"message_id" => "42"}
        },
        ex_gram_module: CapturingExGram
      )

      assert_received {:ex_gram_rich, 99, %InputRichMessage{}, opts}
      assert %ReplyParameters{message_id: 42} = opts[:reply_parameters]
    end

    test "passes an already-built InputRichMessage through untouched" do
      built = %InputRichMessage{html: "<b>hi</b>"}

      ExGramClient.call(
        "bot-token",
        "sendRichMessage",
        %{"chat_id" => 99, "rich_message" => built},
        ex_gram_module: CapturingExGram
      )

      assert_received {:ex_gram_rich, 99, ^built, _opts}
    end

    test "drops unknown keys when building an InputRichMessage" do
      ExGramClient.call(
        "bot-token",
        "sendRichMessage",
        %{"chat_id" => 99, "rich_message" => %{"markdown" => "hi", "bogus" => "x"}},
        ex_gram_module: CapturingExGram
      )

      assert_received {:ex_gram_rich, 99, %InputRichMessage{markdown: "hi"}, _opts}
    end

    test "supports every InputRichMessage field" do
      ExGramClient.call(
        "bot-token",
        "sendRichMessage",
        %{
          "chat_id" => 99,
          "rich_message" => %{
            "html" => "<b>hi</b>",
            "is_rtl" => true,
            "skip_entity_detection" => true
          }
        },
        ex_gram_module: CapturingExGram
      )

      assert_received {:ex_gram_rich, 99, rich_message, _opts}
      assert rich_message.html == "<b>hi</b>"
      assert rich_message.is_rtl == true
      assert rich_message.skip_entity_detection == true
    end

    test "editMessageText dispatches rich edits to edit_message_text/1" do
      ExGramClient.call(
        "bot-token",
        "editMessageText",
        %{"chat_id" => 99, "message_id" => 7, "rich_message" => %{"markdown" => @table}},
        ex_gram_module: CapturingExGram
      )

      assert_received {:ex_gram_edit_rich, opts}
      assert %InputRichMessage{markdown: @table} = opts[:rich_message]
      assert opts[:chat_id] == 99
      assert opts[:message_id] == 7
    end

    test "editMessageText still dispatches plain edits to edit_message_text/2" do
      ExGramClient.call(
        "bot-token",
        "editMessageText",
        %{"chat_id" => 99, "message_id" => 7, "text" => "plain", "parse_mode" => "HTML"},
        ex_gram_module: CapturingExGram
      )

      assert_received {:ex_gram_edit_plain, "plain", opts}
      assert opts[:parse_mode] == "HTML"
      refute Keyword.has_key?(opts, :rich_message)
    end
  end
end
