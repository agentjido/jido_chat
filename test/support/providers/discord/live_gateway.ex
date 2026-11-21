defmodule Jido.Chat.Discord.LiveGateway do
  @moduledoc false
  import ExUnit.Assertions
  import ExUnit.Callbacks, only: [start_supervised!: 1]
  import Jido.Chat.LiveCase, only: [on_cleanup: 1]
  alias Jido.Chat
  alias Jido.Chat.Discord.LiveHelpers, as: L

  def reply(%{client: c, room: room}) do
    {:ok, _} = Application.ensure_all_started(:jido)
    start_supervised!({Jido, name: Jido.Chat.Discord.LiveJido})
    definition = Jido.Chat.Discord.LiveAgent.definition()
    [entry] = definition.plugins
    [connection] = entry.data.connections
    # Agent definitions use data that can be serialized. The test Client tracks calls with local process references.
    connection = %{connection | client: Map.take(c, [:adapter, :id, :credentials]), rooms: [room]}
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

    sent =
      Chat.send_text(c, room, "jido-discord-source-probe:#{c.config[:live_run_id]}")
      |> L.complete(c)
      |> then(&L.track_message(c, room, &1))

    wait_until(fn -> Jido.AgentServer.snapshot(server).agent.state.reply_id != "" end, 20_000)
    state = Jido.AgentServer.snapshot(server).agent.state
    assert state.received_id == sent["id"]
    assert state.delivery_type == "jido.chat.command.send_message.completed"
    on_cleanup(fn -> L.remove_message(c, room, state.reply_id) end)
    reply = L.execute(c, Chat.Signal.FetchMessage, %{"room_id" => room, "message_id" => state.reply_id})
    assert reply["text"] == "jido-discord-source-reply:" <> sent["id"]
    assert reply["reply_to_id"] == sent["id"]
    sensor = :global.whereis_name(sensor_name)
    worker = :sys.get_state(sensor).worker
    connection = :sys.get_state(worker).connection
    ref = Process.monitor(connection)
    :ok = Jido.stop_agent(Jido.Chat.Discord.LiveJido, server)
    assert_receive {:DOWN, ^ref, :process, ^connection, _}, 5_000
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
