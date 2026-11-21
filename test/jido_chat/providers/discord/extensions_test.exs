defmodule Jido.Chat.Discord.ExtensionsTest do
  use ExUnit.Case, async: true
  import Jido.Chat.Discord.Fixtures
  @moduletag capture_log: true

  test "rich messages preserve embeds, native controls and reply routing" do
    test = self()

    c =
      client(fn _, :post, path, payload ->
        send(test, {path, payload})
        {:ok, message()}
      end)

    s =
      request(Jido.Chat.Discord.Signal.SendRichMessage, %{
        "room_id" => "202",
        "text" => "hi",
        "embeds" => [%{"title" => "hello"}],
        "components" => [],
        "tts" => true
      })

    assert {:ok, _} = Jido.Chat.execute(c, s)
    assert_receive {"/channels/202/messages", %{"embeds" => [%{"title" => "hello"}], "tts" => true}}

    s =
      request(Jido.Chat.Discord.Signal.StartMessageThread, %{
        "room_id" => "202",
        "message_id" => "101",
        "name" => "thread"
      })

    c =
      client(fn _, :post, path, payload ->
        send(test, {path, payload})
        {:ok, %{"id" => "thread", "name" => "thread", "parent_id" => "202"}}
      end)

    assert {:ok, result} = Jido.Chat.execute(c, s)
    assert result.data["result"]["parent_message_id"] == "101"
    assert_receive {"/channels/202/messages/101/threads", %{"name" => "thread"}}

    for action <- Jido.Chat.Discord.actions() do
      assert %{"input_schema" => _, "output_schema" => _} = action.authoring_contract()
      assert is_map(action.result_schema())
    end
  end

  test "shared keyboard buttons become Discord components" do
    c =
      client(fn _, _, _, payload ->
        assert payload["components"] == [
                 %{
                   "type" => 1,
                   "components" => [
                     %{"type" => 2, "style" => 1, "label" => "Action", "custom_id" => "action"},
                     %{"type" => 2, "style" => 5, "label" => "Link", "url" => "https://example.com"}
                   ]
                 }
               ]

        {:ok, message()}
      end)

    assert {:ok, _} =
             Jido.Chat.send_text(c, "202", "hello",
               keyboard: %{
                 "rows" => [
                   [%{"text" => "Action", "value" => "action"}, %{"text" => "Link", "url" => "https://example.com"}]
                 ]
               }
             )
  end

  test "webhook verifies the exact body with a private public-key setting" do
    {public, private} = :crypto.generate_key(:eddsa, :ed25519)
    c = %{client() | credentials: %{public_key: Base.encode16(public)}}
    body = ~s({"type":1})
    timestamp = "100"
    signature = :crypto.sign(:eddsa, :none, timestamp <> body, [private, :ed25519]) |> Base.encode16()
    headers = [{"X-Signature-Timestamp", timestamp}, {"X-Signature-Ed25519", signature}]
    assert :ok = Jido.Chat.Discord.Webhook.verify(c, body, headers)
    assert {:error, :invalid_signature} = Jido.Chat.Discord.Webhook.verify(c, body <> " ", headers)
    assert {:error, :invalid_signature} = Jido.Chat.Discord.Webhook.verify(c, body, [])

    assert {:error, :invalid_signature} =
             Jido.Chat.Discord.Webhook.verify(%{c | credentials: %{public_key: "invalid"}}, body, headers)

    assert {:error, :missing_public_key} = Jido.Chat.Discord.Webhook.verify(client(), body, headers)
    assert {:error, :invalid_signature} = Jido.Chat.Discord.Webhook.verify(c, body, [{nil, nil}, :bad])
  end
end
