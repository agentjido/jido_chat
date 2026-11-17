defmodule Jido.Chat.RuntimeBusTest do
  use ExUnit.Case, async: false

  alias Jido.Chat.{Content, Post}
  alias Jido.Chat.Runtime.Signal.Room.{AddReaction, Join}
  alias Jido.Chat.Runtime.Storage.Memory
  alias Jido.Chat.Runtime.Supervisor, as: RuntimeSupervisor

  defmodule Runtime do
    use Jido.Chat.Runtime,
      jido: Jido.Chat.RuntimeBusTest.Jido,
      storage: {Memory, Jido.Chat.RuntimeBusTest.Storage},
      room_definitions: %{
        "first" => Jido.Chat.RuntimeBusTest.FirstRoom,
        "second" => Jido.Chat.RuntimeBusTest.SecondRoom
      }
  end

  defmodule FirstRoom do
    use Jido.Chat.Runtime.Room, name: "runtime_bus_first_room"

    room do
      admin("operator")
      runtime(Runtime)
    end
  end

  defmodule SecondRoom do
    use Jido.Chat.Runtime.Room, name: "runtime_bus_second_room"

    room do
      admin("operator")
      runtime(Runtime)
    end
  end

  setup do
    {:ok, _} = Application.ensure_all_started(:jido)

    start_supervised!(
      {Jido, name: __MODULE__.Jido, namespace: "runtime-bus-test-#{System.unique_integer([:positive])}"}
    )

    start_supervised!({Memory, name: __MODULE__.Storage})
    start_runtime()
    :ok
  end

  test "starts one bounded Bus before the Runtime manager is ready" do
    assert {:ok, bus} = Runtime.runtime_bus()
    assert Process.alive?(bus)
    assert {:ok, %{ready: true}} = Runtime.runtime_status()

    supervisor = Process.whereis(RuntimeSupervisor.supervisor_name(Runtime))
    manager = Process.whereis(RuntimeSupervisor.manager_name(Runtime))
    children = Supervisor.which_children(supervisor)

    assert length(children) == 2
    assert Enum.any?(children, fn {_id, pid, :worker, modules} -> pid == bus and Jido.Signal.Bus in modules end)

    assert Enum.any?(children, fn {_id, pid, :worker, modules} ->
             pid == manager and Jido.Chat.Runtime.Manager in modules
           end)

    assert {:error, :runtime_not_started} = Jido.Chat.Runtime.Bus.whereis(Enum)

    assert {:stop, {:invalid_runtime_option, :bus_max_log_size}} =
             RuntimeSupervisor.init({Runtime, bus_max_log_size: 0})
  end

  test "fans committed facts from dynamic Rooms to one native subscriber" do
    assert {:ok, message_subscription} = Runtime.subscribe_runtime("jido.chat.room.message")
    assert {:ok, _reaction_subscription} = Runtime.subscribe_runtime("jido.chat.reaction.*")
    provision("first-room", "first")
    provision("second-room", "second")
    join("first-room", "alice", "operator")
    join("second-room", "alice", "operator")

    first = post("first-room", "first message", "alice")
    second = post("second-room", "second message", "alice")

    assert_receive {:signal, %Jido.Signal{type: "jido.chat.room.message"} = first_fact}
    assert_receive {:signal, %Jido.Signal{type: "jido.chat.room.message"} = second_fact}

    assert MapSet.new([first_fact.data["room"].id, second_fact.data["room"].id]) ==
             MapSet.new(["first-room", "second-room"])

    add = AddReaction.new!(%{"message_id" => first.id, "reaction" => "eyes"})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(Runtime.jido(), room("first-room"), add, context: %{actor: "alice"})

    assert_receive {:signal, %Jido.Signal{type: "jido.chat.reaction.added", data: reaction_data}}
    assert reaction_data["room_id"] == "first-room"
    assert reaction_data["message_id"] == first.id

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(Runtime.jido(), room("first-room"), add, context: %{actor: "alice"})

    refute_receive {:signal, %Jido.Signal{type: "jido.chat.reaction.added"}}, 50

    rejected = AddReaction.new!(%{"message_id" => second.id, "reaction" => "eyes"})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed}} =
             Jido.call(Runtime.jido(), room("second-room"), rejected, context: %{actor: "outsider"})

    refute_receive {:signal, %Jido.Signal{type: "jido.chat.reaction.added"}}, 50
    assert :ok = Runtime.unsubscribe_runtime(message_subscription)
    _third = post("first-room", "not observed", "alice")
    refute_receive {:signal, %Jido.Signal{type: "jido.chat.room.message"}}, 50
  end

  test "removes an ordinary subscription when its target exits" do
    parent = self()

    target =
      spawn(fn ->
        result = Runtime.subscribe_runtime("jido.chat.room.message")
        send(parent, {:subscribed, self(), result})
        receive do: (:stop -> :ok)
      end)

    assert_receive {:subscribed, ^target, {:ok, _subscription}}
    assert {:ok, bus} = Runtime.runtime_bus()
    assert map_size(:sys.get_state(bus).subscriptions) == 1
    monitor = Process.monitor(target)
    send(target, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^target, :normal}
    assert :ok = await_subscription_count(bus, 0)
  end

  test "a host reattaches after a Runtime restart" do
    provision("first-room", "first")
    join("first-room", "alice", "operator")
    assert {:ok, _subscription} = Runtime.subscribe_runtime("jido.chat.room.message")
    _first = post("first-room", "before restart", "alice")
    assert_receive {:signal, %Jido.Signal{type: "jido.chat.room.message"}}
    assert {:ok, first_bus} = Runtime.runtime_bus()
    monitor = Process.monitor(first_bus)

    assert :ok = stop_supervised(Runtime)
    assert_receive {:DOWN, ^monitor, :process, ^first_bus, _reason}
    assert {:error, :runtime_not_started} = Runtime.runtime_bus()

    start_runtime()
    assert {:ok, second_bus} = Runtime.runtime_bus()
    refute second_bus == first_bus
    assert {:ok, %{state: :running}} = Runtime.room_runtime_status("first-room")
    assert {:ok, _subscription} = Runtime.subscribe_runtime("jido.chat.room.message")
    _second = post("first-room", "after restart", "alice")
    assert_receive {:signal, %Jido.Signal{type: "jido.chat.room.message"}}
  end

  test "keeps durable state when the Runtime Bus is unavailable" do
    provision("first-room", "first")
    join("first-room", "alice", "operator")
    assert {:ok, bus} = Runtime.runtime_bus()
    supervisor = Process.whereis(RuntimeSupervisor.supervisor_name(Runtime))
    monitor = Process.monitor(bus)
    assert :ok = :sys.suspend(supervisor)

    try do
      Process.exit(bus, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^bus, :killed}
      assert {:error, :runtime_not_started} = Runtime.runtime_bus()
      message = post("first-room", "stored without notification", "alice")
      assert {:ok, stored} = Runtime.get_room_history("first-room", message.id)
      assert stored.message_id == message.id
    after
      :ok = :sys.resume(supervisor)
    end

    assert {:ok, replacement} = await_runtime_bus(bus)
    assert Process.alive?(replacement)
  end

  defp start_runtime do
    start_supervised!({Runtime, reconcile_interval: :infinity, bus_max_log_size: 20})
  end

  defp provision(id, definition_key) do
    assert {:ok, %{activation: {:ok, %{state: :running}}}} =
             Runtime.provision_room(definition_key, %{id: id, kind: :group})
  end

  defp join(room_id, member, actor) do
    request = Join.new!(%{"member" => member})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(Runtime.jido(), room(room_id), request, context: %{actor: actor})
  end

  defp post(room_id, text, actor) do
    post = Post.new(%{content: [Content.text(text)]})
    request = Jido.Chat.Runtime.Signal.Room.Post.new!(%{"post" => Post.to_map(post), "mentions" => []})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed, reply: reply}} =
             Jido.call(Runtime.jido(), room(room_id), request, context: %{actor: actor})

    reply.data["message"]
  end

  defp room(id) do
    {:ok, room} = Jido.agent_address(Runtime.jido(), id)
    room
  end

  defp await_subscription_count(bus, count, attempts \\ 100)
  defp await_subscription_count(_bus, _count, 0), do: flunk("subscription target was not removed")

  defp await_subscription_count(bus, count, attempts) do
    if map_size(:sys.get_state(bus).subscriptions) == count do
      :ok
    else
      Process.sleep(10)
      await_subscription_count(bus, count, attempts - 1)
    end
  end

  defp await_runtime_bus(previous, attempts \\ 100)
  defp await_runtime_bus(_previous, 0), do: {:error, :runtime_not_started}

  defp await_runtime_bus(previous, attempts) do
    case Runtime.runtime_bus() do
      {:ok, bus} when bus != previous ->
        {:ok, bus}

      _result ->
        Process.sleep(10)
        await_runtime_bus(previous, attempts - 1)
    end
  end
end
