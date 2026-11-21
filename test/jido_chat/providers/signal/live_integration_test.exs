defmodule Jido.Chat.Signal.LiveIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :live

  @run_live System.get_env("RUN_LIVE_SIGNAL_TESTS") in ["1", "true", "TRUE", "yes"]
  @target System.get_env("SIGNAL_TEST_RECIPIENT")

  if not @run_live do
    @moduletag skip: "set RUN_LIVE_SIGNAL_TESTS=true to run live Signal tests"
  end

  if @run_live and @target in [nil, ""] do
    raise "live Signal tests require SIGNAL_TEST_RECIPIENT"
  end

  alias Jido.Chat.Client
  alias Jido.Chat.Signal.{Adapter, Transport.CliClient, Transport.JsonRpcClient}

  test "sends live Signal text and file requests through Jido Chat" do
    text = "jido signal live #{System.system_time(:millisecond)}"
    client = live_client()

    assert {:ok, response} = Jido.Chat.send_text(client, @target, text)
    assert response.data["result"]["id"]

    source = %{
      "content_base64" => Base.encode64(text <> "\n"),
      "filename" => "jido-signal-live.txt"
    }

    assert {:ok, media_response} =
             Jido.Chat.send_file(client, @target, source, caption: text <> " attachment")

    assert media_response.data["result"]["id"]

    assert {:ok, quote_response} =
             Jido.Chat.send_text(client, @target, text <> " quote", reply_to_id: response.data["result"]["id"])

    assert quote_response.data["result"]["id"]
  end

  defp live_client do
    transport =
      if String.downcase(System.get_env("SIGNAL_TRANSPORT") || "cli") == "cli",
        do: CliClient,
        else: JsonRpcClient

    Client.new!(Adapter,
      id: "signal-live",
      transport: transport,
      credentials: %{account: System.get_env("SIGNAL_ACCOUNT")},
      config: [
        endpoint: System.get_env("SIGNAL_RPC_ENDPOINT"),
        executable: System.get_env("SIGNAL_CLI_PATH") || "signal-cli"
      ]
    )
  end
end
