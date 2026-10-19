defmodule Jido.Chat.PluginConfigTest do
  use ExUnit.Case, async: false
  alias Jido.Chat.Plugin

  setup do
    {:ok, _} = Application.ensure_all_started(:jido)
    start_supervised!({Jido, name: __MODULE__.Jido})
    :ok
  end

  defp connection do
    [entry] = Jido.Chat.PluginFixture.SensorAgent.definition().extensions
    hd(entry.data.connections)
  end

  test "a connection name cannot collide with the internal Runtime child ID" do
    c = %{connection() | name: Plugin.Runtime}
    root = start_supervised!(Plugin.child_spec(%{options: [connections: [c]], agent_server: self()}))
    children = Supervisor.which_children(root)
    assert {Plugin.Runtime, sensor, :worker, [Jido.Chat.Sensor]} = List.keyfind(children, Plugin.Runtime, 0)
    assert Process.alive?(sensor)

    assert {{Plugin.Runtime, :connections}, runtime, :worker, [Plugin.Runtime]} =
             List.keyfind(children, {Plugin.Runtime, :connections}, 0)

    assert Process.alive?(runtime)
  end

  test "Sensor is a child of the Agent Plugin; Dispatch admits only the named scope" do
    definition = Jido.Chat.PluginFixture.SensorAgent.definition()
    {:ok, server} = Jido.start_agent(__MODULE__.Jido, definition, id: "sensor")
    :ok = Jido.AgentServer.await_ready(server)
    [connection] = Plugin.connections(server)

    signal =
      Jido.Chat.Signal.Policy.new!(
        Jido.Chat.Signal.MessageReceived,
        %{
          "item_id" => "one",
          "delivery_id" => "batch",
          "room_id" => "room-1",
          "message_id" => "one",
          "sender" => %{"id" => "human"},
          "text" => "hello"
        },
        source: connection.client.source
      )

    assert :ok =
             Jido.Signal.Dispatch.dispatch(
               signal,
               {Plugin.Ingress, server: server, connection: :mock}
             )

    assert {:error, :unknown_chat_connection} =
             Jido.Signal.Dispatch.dispatch(
               signal,
               {Plugin.Ingress, server: server, connection: :missing}
             )

    assert {:error, :invalid_chat_signal} = Plugin.ingest(server, :mock, :bad)

    assert {:error, :undeclared_sensor_signal} =
             Plugin.ingest(server, :mock, %{signal | type: "jido.chat.message.updated"})

    [{_, root, _, _}] = Supervisor.which_children(Jido.agent_supervisor_name(__MODULE__.Jido))
    {_, plugin, _, _} = Enum.find(Supervisor.which_children(root), &(elem(&1, 0) == {:plugin, Plugin}))
    {:mock, sensor, _, _} = Enum.find(Supervisor.which_children(plugin), &(elem(&1, 0) == :mock))
    assert Process.alive?(sensor)
    send(sensor, :poll)
    assert :sys.get_state(sensor).cursor == nil
    GenServer.stop(server)
    ref = Process.monitor(sensor)
    assert_receive {:DOWN, ^ref, :process, ^sensor, _}, 2_000
  end

  test "configuration rejects duplicate names, invalid modules, unsupported patterns and options" do
    c = connection()

    for changes <- [
          %{rooms: []},
          %{rooms: [42]},
          %{rooms: :all},
          %{client: %{adapter: String, id: "bad"}},
          %{commands: [String]},
          %{source: %{c.source | module: String}},
          %{source: %{c.source | module: String}},
          %{source: %{c.source | options: [:bad]}},
          %{source: %{c.source | options: [:bad]}},
          %{source: %{c.source | emit: "other.*"}},
          %{source: %{module: Jido.Chat.Sensor}}
        ] do
      assert {:error, :invalid_chat_config} = Plugin.normalize(%{connections: [Map.merge(c, changes)]})
    end

    assert {:error, _} = Plugin.normalize(%{connections: [c, c]})
    assert {:ok, _} = Plugin.normalize(%{connections: [%{c | rooms: [Jido.Config.env("ROOM")]}]})
  end

  test "verification requires a route for each advertised fact" do
    c = connection()
    definition = Jido.Chat.PluginFixture.SensorAgent.definition()

    assert {:error, {:unhandled_sensor_signal, :mock, "jido.chat.message.received"}} =
             Plugin.verify(%{connections: [c]}, %{definition | routes: []})

    assert :ok = Plugin.verify(%{connections: [%{c | source: nil}]}, definition)
  end

  test "callback room grants are scoped, expire, and are pruned" do
    {:ok, runtime} = Plugin.Runtime.start_link({self(), []})
    on_exit(fn -> if Process.alive?(runtime), do: GenServer.stop(runtime) end)
    signal = %{data: %{"interaction_id" => "button", "room_id" => "room-1"}}
    assert :ok = GenServer.call(runtime, {:admit, "first", signal})
    assert "room-1" == GenServer.call(runtime, {:interaction_room, "first", "button"})
    assert nil == GenServer.call(runtime, {:interaction_room, "second", "button"})

    :sys.replace_state(runtime, fn s ->
      %{s | interactions: %{{"first", "button"} => {"room-1", System.monotonic_time(:second) - 1}}}
    end)

    assert nil == GenServer.call(runtime, {:interaction_room, "first", "button"})
    GenServer.call(runtime, {:admit, "first", %{data: %{}}})
    assert :sys.get_state(runtime).interactions == %{}
  end

  test "verification names both overlapping routes and the missing connection fact" do
    c = connection()
    definition = Jido.Chat.PluginFixture.SensorAgent.definition()
    [route] = definition.routes
    overlapping = %{definition | routes: [route, %{route | path: "jido.chat.**"}]}

    assert {:error, {:overlapping_chat_routes, "jido.chat.message.received", "jido.chat.**"}} =
             Plugin.verify(%{connections: [c]}, overlapping)

    assert {:ok, _} = Plugin.normalize(%{connections: [%{c | source: %{c.source | emit: ["jido.chat.message.*"]}}]})
  end

  test "activation rejects unsupported Actions and identifies unresolved fields without values" do
    c = connection()
    init = %{options: [connections: [%{c | commands: [Jido.Chat.StartTyping]}]], agent_server: self()}

    assert_raise ArgumentError, ~r/connection mock: unsupported Action Jido.Chat.StartTyping/, fn ->
      Plugin.child_spec(init)
    end

    c = put_in(c.client[:credentials], %{token: Jido.Config.env("JIDO_CHAT_TEST_MISSING_92EC")})

    assert_raise ArgumentError, ~r/connection mock: cannot resolve client.credentials.token/, fn ->
      Plugin.child_spec(%{init | options: [connections: [c]]})
    end
  end

  test "one Sensor restart leaves the other connection running and readiness is local" do
    c = connection()
    second = %{c | name: :front_desk, client: %{c.client | id: "mock/front-desk"}}
    root = start_supervised!(Plugin.child_spec(%{options: [connections: [c, second]], agent_server: self()}))
    children = Map.new(Supervisor.which_children(root), fn {name, pid, _, _} -> {name, pid} end)
    assert :ok = Plugin.await_ready(root, [])

    assert %{mock: %{process: :running, provider: :unknown}, front_desk: %{process: :running, provider: :unknown}} =
             Plugin.status(self())

    assert %{process: :running, provider: :unknown} = Jido.Chat.Sensor.status(children.mock)
    Process.exit(children.mock, :kill)
    await_restart(root, children.mock, 100)
    after_restart = Map.new(Supervisor.which_children(root), fn {name, pid, _, _} -> {name, pid} end)
    assert after_restart.front_desk == children.front_desk
    assert Process.alive?(children.front_desk)
    send(after_restart.mock, :poll)
    assert Jido.Chat.Sensor.status(after_restart.mock).provider == :read_succeeded
    assert Plugin.status(self()).mock.provider == :read_succeeded
  end

  defp await_restart(_root, _old, 0), do: flunk("Sensor did not restart")

  defp await_restart(root, old, tries) do
    case Enum.find(Supervisor.which_children(root), &(elem(&1, 0) == :mock)) do
      {:mock, pid, _, _} when is_pid(pid) and pid != old ->
        :ok

      _ ->
        Process.sleep(10)
        await_restart(root, old, tries - 1)
    end
  end
end
