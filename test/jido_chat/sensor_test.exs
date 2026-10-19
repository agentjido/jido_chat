defmodule Jido.Chat.SensorTest do
  use ExUnit.Case, async: false
  alias Jido.Chat.{Client, Sensor}

  defmodule Source do
    @behaviour Jido.Chat.Sensor.Source
    def mode, do: :poll
    def poll_interval(options), do: Keyword.get(options, :interval, 1_000)
    def signal_types, do: ["jido.chat.message.received"]

    def read(client, cursor, opts) do
      send(opts[:observer], {:read, cursor})

      Agent.get_and_update(client.config[:store], fn
        [head | tail] -> {head, tail}
        [] -> {{:ok, [], cursor}, []}
      end)
    end
  end

  defmodule Dispatch do
    @behaviour Jido.Signal.Dispatch.Adapter
    def options_schema, do: Zoi.keyword(store: Zoi.pid(), observer: Zoi.pid())

    def deliver(signal, opts) do
      Agent.get_and_update(opts[:store], fn
        [false | tail] -> {{:error, :busy}, tail}
        [_ | tail] -> {send_signal(signal, opts), tail}
        [] -> {send_signal(signal, opts), []}
      end)
    end

    defp send_signal(signal, opts) do
      send(opts[:observer], {:accepted, signal})
      :ok
    end
  end

  defp fact(client, id, room \\ "room-1") do
    Jido.Chat.Signal.MessageReceived.new!(
      %{
        "delivery_id" => "batch",
        "item_id" => id,
        "room_id" => room,
        "message_id" => id,
        "sender" => %{"id" => "human"},
        "text" => "hello"
      },
      source: client.source
    )
  end

  defp setup_sensor(batches, changes \\ []) do
    store = start_supervised!({Agent, fn -> [] end})
    client = Client.new!(Jido.Chat.PluginFixture.Adapter, id: "sensor", config: [store: store])
    batches = batches.(client)
    Agent.update(store, fn _ -> batches end)

    opts =
      Keyword.merge(
        [
          client: client,
          source: Source,
          interval: 60_000,
          emit: "jido.chat.message.received",
          options: [observer: self()],
          dispatch: {:pid, target: self()}
        ],
        changes
      )

    pid = start_supervised!({Sensor, opts})
    {pid, client}
  end

  defp poll(pid) do
    send(pid, :poll)
    :sys.get_state(pid)
  end

  test "a non-Telegram source dispatches to a PID without an Agent" do
    {pid, _} = setup_sensor(fn client -> [{:ok, [fact(client, "one")], 42}] end)
    assert poll(pid).cursor == 42
    assert_receive {:read, nil}
    assert_receive {:signal, %Jido.Signal{data: %{"item_id" => "one"}}}
    assert poll(pid).cursor == 42
    assert_receive {:read, 42}
  end

  test "partial delivery retries only unaccepted events before committing the cursor" do
    dispatch = start_supervised!({Agent, fn -> [true, false, true] end}, id: :dispatch)

    {pid, _} =
      setup_sensor(
        fn client ->
          batch = {:ok, [fact(client, "one"), fact(client, "two")], 3}
          [batch, batch]
        end,
        dispatch: {Dispatch, store: dispatch, observer: self()}
      )

    assert poll(pid).cursor == nil
    assert_receive {:accepted, %{data: %{"item_id" => "one"}}}
    refute_receive {:accepted, _}
    assert poll(pid).cursor == 3
    assert_receive {:accepted, %{data: %{"item_id" => "two"}}}
    refute_receive {:accepted, _}
  end

  test "read errors keep the Sensor alive and retain its cursor" do
    {pid, _} = setup_sensor(fn _ -> [{:error, :offline}, {:ok, [], 2}] end)
    assert poll(pid).cursor == nil
    assert Process.alive?(pid)
    assert poll(pid).cursor == 2
  end

  test "room filters advance the cursor without dispatching excluded facts" do
    {pid, _} = setup_sensor(fn c -> [{:ok, [fact(c, "one", "other")], 2}] end, rooms: ["room-1"])
    assert poll(pid).cursor == 2
    refute_receive {:signal, _}
  end

  test "invalid facts and foreign sources cannot pass the boundary" do
    for change <- [
          fn s -> %{s | source: "foreign"} end,
          fn s -> %{s | data: %{}} end,
          fn s -> %{s | type: "other.event"} end,
          fn _ -> :invalid end
        ] do
      {pid, _} = setup_sensor(fn c -> [{:ok, [change.(fact(c, "one"))], 2}] end)
      assert poll(pid).cursor == nil
      refute_receive {:signal, _}
      stop_supervised(Sensor)
      stop_supervised(Agent)
    end
  end

  test "duplicate retention is bounded" do
    {pid, _} =
      setup_sensor(fn c ->
        [{:ok, Enum.map(1..1025, &fact(c, to_string(&1))), 1026}]
      end)

    state = poll(pid)
    assert MapSet.size(state.seen) == 1024
    refute MapSet.member?(state.seen, {"jido.chat.message.received", "1"})
  end

  test "invalid settings fail before a process starts" do
    client = Client.new!(Jido.Chat.PluginFixture.Adapter, id: "invalid")
    base = [client: client, source: Source, emit: "jido.chat.**", dispatch: {:pid, target: self()}]

    for changes <- [
          [client: nil],
          [source: String],
          [source: nil],
          [interval: 0],
          [emit: "other.*"],
          [options: [:invalid]],
          [rooms: [42]],
          [dispatch: :invalid]
        ] do
      assert {:error, :invalid_sensor_options} = Sensor.start_link(Keyword.merge(base, changes))
    end
  end
end
