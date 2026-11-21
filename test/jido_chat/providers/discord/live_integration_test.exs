defmodule Jido.Chat.Discord.LiveIntegrationTest do
  use ExUnit.Case, async: false
  @moduletag :live
  @moduletag capture_log: true
  unless System.get_env("RUN_LIVE_DISCORD_TESTS") in ["1", "true", "TRUE", "yes", "on"] do
    @moduletag skip: "set RUN_LIVE_DISCORD_TESTS=true to run live Discord tests"
  end

  defp request(definition, client, data),
    do: definition.new!(Map.merge(%{"client_id" => client.id, "request_id" => Jido.Id.uuid7()}, data))

  defp result({:ok, signal}), do: signal.data["result"]
  defp result(other), do: flunk("Chat request failed: #{inspect(other)}")

  defp fetch(c, room, id),
    do:
      Jido.Chat.execute(c, request(Jido.Chat.Signal.FetchMessage, c, %{"room_id" => room, "message_id" => id}))
      |> result()

  defp cleanup(c, room, id), do: Jido.Chat.Discord.LiveHelpers.remove_message(c, room, id)

  setup_all do
    token = System.fetch_env!("DISCORD_BOT_TOKEN")
    room = System.fetch_env!("DISCORD_TEST_CHANNEL_ID")
    client = Jido.Chat.Client.new!(Jido.Chat.Discord.Adapter, id: "discord-live", credentials: %{token: token})
    # Check that the configured channel belongs to the authorized server.
    {:ok, channel} = client.transport.call(token, :get, "/channels/" <> room, nil, [])
    {:ok, guild} = client.transport.call(token, :get, "/guilds/" <> channel["guild_id"], nil, [])
    assert guild["name"] == "agentjido-test"
    IO.puts("Discord live target: #{guild["name"]} / #{channel["name"]} (#{room})")
    {:ok, client: client, room: room}
  end

  test "live Gateway -> shared Sensor -> V3 Agent -> Chat reply", %{client: c, room: room} do
    {:ok, _} = Application.ensure_all_started(:jido)
    start_supervised!({Jido, name: Jido.Chat.Discord.LiveJido})
    definition = Jido.Chat.Discord.LiveAgent.definition()
    [entry] = definition.plugins
    [connection] = entry.data.connections
    connection = %{connection | client: Map.take(c, [:adapter, :id, :credentials, :config, :transport]), rooms: [room]}
    definition = %{definition | plugins: [%{entry | data: %{entry.data | connections: [connection]}}]}
    {:ok, server} = Jido.start_agent(Jido.Chat.Discord.LiveJido, definition, id: "discord-live-proof")
    assert :ok = Jido.AgentServer.await_ready(server)
    sensor_name = {Jido.Chat.Sensor, Jido.Chat.Discord.Source, Jido.Chat.Discord.Source.key(c, [])}

    wait_until(
      fn ->
        case :global.whereis_name(sensor_name) do
          :undefined ->
            false

          pid ->
            worker = :sys.get_state(pid).worker
            is_pid(worker) and :sys.get_state(worker).session != nil
        end
      end,
      30_000
    )

    sent = Jido.Chat.send_text(c, room, "jido-discord-source-probe:#{System.unique_integer([:positive])}") |> result()
    on_exit(fn -> cleanup(c, room, sent["id"]) end)
    wait_until(fn -> Jido.AgentServer.snapshot(server).agent.state.reply_id != "" end, 20_000)
    state = Jido.AgentServer.snapshot(server).agent.state
    assert state.received_id == sent["id"]
    assert state.delivery_type == "jido.chat.command.send_message.completed"
    on_exit(fn -> cleanup(c, room, state.reply_id) end)
    reply = fetch(c, room, state.reply_id)
    assert reply["text"] == "jido-discord-source-reply:" <> sent["id"]
    assert reply["reply_to_id"] == sent["id"]
    sensor = :global.whereis_name(sensor_name)
    worker = :sys.get_state(sensor).worker
    connection = :sys.get_state(worker).connection
    ref = Process.monitor(connection)
    :ok = Jido.stop_agent(Jido.Chat.Discord.LiveJido, server)
    assert_receive {:DOWN, ^ref, :process, ^connection, _}, 5_000
    IO.puts("Discord Gateway/Sensor/Agent reply proof passed: #{sent["id"]} -> #{state.reply_id}; connection stopped")
  end

  defp wait_until(check, timeout), do: do_wait(check, System.monotonic_time(:millisecond) + timeout)

  defp do_wait(check, deadline) do
    if check.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline, do: flunk("live proof timed out")
      Process.sleep(100)
      do_wait(check, deadline)
    end
  end
end
