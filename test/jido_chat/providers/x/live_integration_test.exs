defmodule Jido.Chat.X.LiveIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.Chat.Client
  alias Jido.Chat.X.Adapter

  @moduletag :live
  @run_live System.get_env("RUN_LIVE_X_TESTS") in ["1", "true", "TRUE", "yes"]
  @run_live_send @run_live and
                   System.get_env("RUN_LIVE_X_SEND_TESTS") in ["1", "true", "TRUE", "yes"]

  if not @run_live do
    @moduletag skip: "set RUN_LIVE_X_TESTS=true to run live X tests"
  end

  if @run_live and
       not Enum.all?(
         ~w(X_CONSUMER_KEY X_CONSUMER_SECRET X_ACCESS_TOKEN X_ACCESS_TOKEN_SECRET),
         &(System.get_env(&1) not in [nil, ""])
       ) do
    raise "live X tests require OAuth 1.0 credentials"
  end

  if @run_live_send and System.get_env("X_TEST_RECIPIENT_ID") in [nil, ""] do
    raise "live X send tests require X_TEST_RECIPIENT_ID"
  end

  test "verifies live X credentials through XDK" do
    client = live_client()

    assert {:ok, %{"data" => %{"id" => id}}} = Xdk.Users.get_me(client)
    assert is_binary(id)
    assert id != ""
  end

  if not @run_live_send do
    @tag skip: "set RUN_LIVE_X_SEND_TESTS=true to send a live X direct message"
  end

  test "sends a live X direct message through XDK" do
    client = live_client()
    text = "jido x live #{System.system_time(:millisecond)}"

    chat =
      Client.new!(Adapter,
        id: "x-live",
        config: [xdk_client: client]
      )

    assert {:ok, response} =
             Jido.Chat.send_text(chat, System.fetch_env!("X_TEST_RECIPIENT_ID"), text)

    assert response.data["result"]["id"]
  end

  defp live_client do
    finch_name = :"Jido.Chat.X.LiveIntegrationTest.Finch.#{System.unique_integer([:positive])}"
    {:ok, _pid} = Finch.start_link(name: finch_name)

    credentials =
      OAuther.credentials(
        consumer_key: System.fetch_env!("X_CONSUMER_KEY"),
        consumer_secret: System.fetch_env!("X_CONSUMER_SECRET"),
        token: System.fetch_env!("X_ACCESS_TOKEN"),
        token_secret: System.fetch_env!("X_ACCESS_TOKEN_SECRET")
      )

    Xdk.new(finch: finch_name, auth: {:oauth1, credentials})
  end
end
