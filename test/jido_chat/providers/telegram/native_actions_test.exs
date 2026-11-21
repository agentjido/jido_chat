defmodule Jido.Chat.Telegram.NativeActionsTest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true
  alias Jido.Chat.Client
  alias Jido.Chat.Telegram, as: Telegram

  defmodule Transport do
    def call(_token, method, payload, opts) do
      send(opts[:observer], {:wire, method, payload})

      case opts[:response] do
        nil -> response(method, payload)
        result -> result
      end
    end

    defp response(method, payload)
         when method in ["sendPhoto", "sendDocument", "sendSticker", "sendAnimation", "sendVideoNote"] do
      field =
        %{
          "sendPhoto" => "photo",
          "sendDocument" => "document",
          "sendSticker" => "sticker",
          "sendAnimation" => "animation",
          "sendVideoNote" => "video_note"
        }[method]

      file = %{"file_id" => "file-1"}
      value = if field == "photo", do: [file], else: file
      {:ok, %{"message_id" => 42, "chat" => %{"id" => payload["chat_id"]}, field => value}}
    end

    defp response("getMe", _), do: {:ok, %ExGram.Model.User{id: 42, username: "bot", first_name: "Bot", is_bot: true}}

    defp response("getFile", payload),
      do: {:ok, %ExGram.Model.File{file_id: payload["file_id"], file_path: "documents/1.json", file_size: 3}}

    defp response("getUpdates", _),
      do:
        {:ok,
         [
           %{
             "update_id" => 10,
             "message" => %{
               "message_id" => 7,
               "chat" => %{"id" => 123, "type" => "private"},
               "from" => %{"id" => 42},
               "text" => "Hello"
             }
           }
         ]}

    defp response(_, _), do: {:ok, true}
  end

  defp client,
    do: Client.new!(Telegram.Adapter, id: "telegram", credentials: %{token: "private-token"}, transport: Transport)

  defp request(action, fields) do
    action.signal_definition().new!(Map.merge(%{"client_id" => "telegram", "request_id" => "request-1"}, fields))
  end

  defp execute(action, fields, opts \\ []) do
    Jido.Chat.Telegram.ActionHelpers.execute(
      action,
      request(action, fields),
      %{client: client(), options: [observer: self()] ++ opts},
      max_attempts: 1
    )
  end

  test "all media Actions accept portable references and upload bytes at the wire boundary" do
    for {action, method, field} <- [
          {Telegram.SendPhoto, "sendPhoto", "photo"},
          {Telegram.SendDocument, "sendDocument", "document"},
          {Telegram.SendSticker, "sendSticker", "sticker"},
          {Telegram.SendAnimation, "sendAnimation", "animation"},
          {Telegram.SendVideoNote, "sendVideoNote", "video_note"}
        ],
        source <- [
          %{"client_id" => "telegram", "kind" => "media", "id" => "telegram://file/source"},
          %{"content_base64" => Base.encode64("file bytes"), "filename" => "fixture.bin"}
        ] do
      assert {:ok, %{signal: completed}} =
               execute(action, %{"room_id" => "123", "source" => source, "thread_id" => "7"})

      assert_receive {:wire, ^method, payload}
      assert payload["message_thread_id"] == "7"

      assert payload[field] ==
               if(Map.has_key?(source, "id"), do: "source", else: {:file_content, "file bytes", "fixture.bin"})

      assert completed.data["result"]["resource_ref"] == %{
               "client_id" => "telegram",
               "id" => "telegram://file/file-1",
               "kind" => "media"
             }

      assert_round_trip(action, completed)
    end
  end

  test "file metadata, bot identity, and callback acknowledgement are typed results" do
    assert {:ok, %{signal: file}} =
             execute(Telegram.GetFile, %{
               "resource_ref" => %{"client_id" => "telegram", "id" => "telegram://file/file-1", "kind" => "media"}
             })

    assert file.data["result"]["file_path"] == "documents/1.json"
    assert_receive {:wire, "getFile", %{"file_id" => "file-1"}}
    assert {:ok, %{signal: bot}} = execute(Telegram.GetMe, %{})
    assert bot.data["result"]["is_bot"]

    assert {:ok, %{signal: answered}} =
             execute(Telegram.AnswerCallbackQuery, %{
               "interaction_id" => "callback",
               "text" => "Done",
               "show_alert" => false
             })

    assert answered.data["result"] == %{"answered" => true, "interaction_id" => "callback"}

    assert_receive {:wire, "answerCallbackQuery",
                    %{"callback_query_id" => "callback", "text" => "Done", "show_alert" => false}}
  end

  test "SendDraft makes one explicit write and does not finalize or schedule a message" do
    for {format, method} <- [
          {"plain", "sendMessageDraft"},
          {"markdown", "sendRichMessageDraft"},
          {"html", "sendRichMessageDraft"}
        ] do
      assert {:ok, %{signal: completed}} =
               execute(Telegram.SendDraft, %{"room_id" => "123", "draft_id" => 7, "text" => "Hello", "format" => format})

      assert completed.data["result"] == %{"acknowledged" => true, "draft_id" => 7}
      assert_receive {:wire, ^method, %{"chat_id" => 123, "draft_id" => 7}}
      refute_receive {:wire, _, _}
    end
  end

  test "FetchUpdates normalizes provider input and returns explicit host offset state" do
    assert {:ok, %{signal: completed}} =
             execute(Telegram.FetchUpdates, %{"offset" => 9, "limit" => 10, "timeout" => 0, "allowed_updates" => []})

    assert_receive {:wire, "getUpdates", %{"offset" => 9, "limit" => 10, "timeout" => 0, "allowed_updates" => []}}
    result = completed.data["result"]
    assert result["next_offset"] == 11
    assert [wire] = result["signals"]
    assert {:ok, fact} = Jido.Signal.Catalog.decode(Jido.Chat.catalog(), Jason.encode!(wire))
    assert fact.type == Jido.Chat.Signal.MessageReceived.type()
    assert fact.data["text"] == "Hello"
    assert {:ok, %{signal: empty}} = execute(Telegram.FetchUpdates, %{"offset" => 11}, response: {:ok, []})
    assert empty.data["result"]["signals"] == []
    assert empty.data["result"]["next_offset"] == 11
  end

  test "invalid base64, foreign references, and wrong clients fail before I/O" do
    valid = %{"room_id" => "123", "source" => %{"content_base64" => Base.encode64("file"), "filename" => "test.txt"}}
    original = request(Telegram.SendDocument, valid)

    for command <- [
          %{original | data: put_in(original.data, ["source", "content_base64"], "not base64")},
          %{
            original
            | data: Map.put(original.data, "source", %{"client_id" => "other", "id" => "file", "kind" => "media"})
          },
          %{original | data: Map.put(original.data, "client_id", "other")}
        ] do
      assert {:error, _} =
               Jido.Chat.Telegram.ActionHelpers.execute(Telegram.SendDocument, command, %{
                 client: client(),
                 options: [observer: self()]
               })
    end

    refute_receive {:wire, _, _}
  end

  test "provider rejection and invalid results retain safe failure Signals" do
    for {response, code} <- [
          {{:error, {:rejected, "private provider details"}}, :provider_failure},
          {{:ok, %{}}, :invalid_provider_result}
        ] do
      assert {:error, %Jido.Chat.Error{code: ^code, signal: failed}} = execute(Telegram.GetMe, %{}, response: response)
      refute inspect(failed) =~ "private"
      assert_round_trip(Telegram.GetMe, failed)
    end
  end

  test "Telegram catalog includes each native Action without changing core operations" do
    assert length(Telegram.actions()) == 14
    assert length(Telegram.signal_definitions()) == 42
    assert length(Jido.Chat.signal_definitions()) == 86
    catalog = Telegram.catalog()

    for action <- Telegram.actions() do
      assert Jido.ChatAction in List.flatten(Keyword.get_values(action.__info__(:attributes), :behaviour))
      assert is_nil(Jido.Chat.Operations.Definitions.lookup(action.signal_definition().type()))
      assert action.signal_definition() in action.signal_definitions()
    end

    assert {:ok, %{signal: completed}} =
             execute(Telegram.GetMe, %{}, response: {:ok, %ExGram.Model.User{id: 42, is_bot: false}})

    assert completed.data["result"]["is_bot"] == false
    assert {:ok, json} = Jido.Signal.Codec.serialize(completed)
    assert {:ok, ^completed} = Jido.Signal.Catalog.decode(catalog, json)
  end

  test "unsupported media captions and non-numeric draft rooms fail before I/O" do
    for action <- [Telegram.SendSticker, Telegram.SendVideoNote] do
      valid =
        request(action, %{
          "room_id" => "123",
          "source" => %{"client_id" => "telegram", "id" => "file", "kind" => "media"}
        })

      assert {:error, _} =
               Jido.Chat.Telegram.ActionHelpers.execute(
                 action,
                 %{valid | data: Map.put(valid.data, "caption", "ignored")},
                 %{
                   client: client(),
                   options: [observer: self()]
                 }
               )
    end

    draft = request(Telegram.SendDraft, %{"room_id" => "123", "draft_id" => 7, "text" => "Hi"})

    assert {:error, _} =
             Jido.Chat.Telegram.ActionHelpers.execute(
               Telegram.SendDraft,
               %{draft | data: Map.put(draft.data, "room_id", "@channel")},
               %{client: client(), options: [observer: self()]}
             )

    refute_receive {:wire, _, _}
  end

  defp assert_round_trip(action, signal) do
    catalog = Jido.Signal.Catalog.new!(Jido.Chat.signal_definitions() ++ action.signal_definitions())
    assert {:ok, json} = Jido.Signal.Codec.serialize(signal)
    assert {:ok, ^signal} = Jido.Signal.Catalog.decode(catalog, json)
    refute json =~ "private-token"
  end
end
