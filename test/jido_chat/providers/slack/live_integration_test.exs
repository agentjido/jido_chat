defmodule Jido.Chat.Slack.LiveIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :live

  test "send, fetch, edit, and delete through the public V3 API" do
    token = System.fetch_env!("SLACK_BOT_TOKEN")
    room_id = System.fetch_env!("SLACK_TEST_CHANNEL_ID")

    client =
      Jido.Chat.Client.new!(Jido.Chat.Slack.Adapter,
        id: "slack/live",
        credentials: %{bot_token: token}
      )

    assert {:ok, sent} = Jido.Chat.send_text(client, room_id, "jido-chat-v3-live")
    message_id = sent.data["result"]["id"]

    on_exit(fn ->
      _ = Jido.Chat.delete_message(client, room_id, message_id)
    end)

    request =
      Jido.Chat.AdapterTestKit.Factories.operation_request(client, :fetch_message, %{
        "room_id" => room_id,
        "message_id" => message_id
      })

    assert {:ok, fetched} = Jido.Chat.execute(client, request)
    assert fetched.data["result"]["text"] == "jido-chat-v3-live"
    assert {:ok, _} = Jido.Chat.edit_message(client, room_id, message_id, "jido-chat-v3-live-edited")
    assert {:ok, _} = Jido.Chat.delete_message(client, room_id, message_id)
  end
end
