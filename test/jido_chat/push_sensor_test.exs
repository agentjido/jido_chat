defmodule Jido.Chat.PushSensorTest do
  use ExUnit.Case, async: false
  @moduletag capture_log: true
  alias Jido.Chat.{Client, Sensor}

  defmodule Source do
    use GenServer
    @behaviour Jido.Chat.Sensor.Source
    def mode, do: :push
    def signal_types, do: ["jido.chat.message.received", "jido.chat.message.updated", "test.chat.room.changed"]
    def start_link(client, sensor, options), do: GenServer.start_link(__MODULE__, {client, sensor, options})

    def init({client, sensor, options}) do
      send(options[:observer], {:source_started, self(), client.id})
      {:ok, sensor}
    end

    def handle_call({:batch, signals}, _from, sensor), do: {:reply, Sensor.push(sensor, signals), sensor}
  end

  defmodule Dispatch do
    @behaviour Jido.Signal.Dispatch.Adapter
    def options_schema, do: Zoi.keyword(store: Zoi.pid(), observer: Zoi.pid())

    def deliver(signal, opts) do
      Agent.get_and_update(opts[:store], fn
        [false | tail] ->
          {{:error, :busy}, tail}

        [_ | tail] ->
          send(opts[:observer], {:accepted, signal})
          {:ok, tail}
      end)
    end
  end

  defmodule FailedSource do
    @behaviour Jido.Chat.Sensor.Source
    def mode, do: :push
    def signal_types, do: ["jido.chat.message.received"]
    def start_link(_, _, _), do: {:error, :offline}
  end

  defmodule InvalidSource do
    def mode, do: :other
    def signal_types, do: []
  end

  defmodule CountingAdapter do
    use Jido.Chat.Adapter
    def capabilities, do: %{}
    def invoke(_, _, _), do: {:error, :unsupported}
    def normalize(_, _, _), do: {:error, :unused}

    def event_definitions do
      if observer = Process.whereis(__MODULE__), do: send(observer, :definitions_read)
      Jido.Chat.event_definitions()
    end
  end

  defmodule TrappingSource do
    @behaviour Jido.Chat.Sensor.Source
    def mode, do: :push
    def signal_types, do: ["jido.chat.message.received"]

    def start_link(client, _sensor, opts) do
      {:ok,
       spawn_link(fn ->
         Process.flag(:trap_exit, true)
         send(opts[:observer], {:source_started, self(), client.id})
         loop(opts[:observer])
       end)}
    end

    defp loop(observer) do
      receive do
        {:EXIT, _parent, :shutdown} ->
          send(observer, :source_ignored_shutdown)
          loop(observer)

        _ ->
          loop(observer)
      end
    end
  end

  defp start(options \\ []) do
    client =
      Keyword.get_lazy(options, :client, fn -> Client.new!(Jido.Chat.PluginFixture.Adapter, id: "push-client") end)

    opts =
      Keyword.merge(
        [
          client: client,
          source: Source,
          options: [observer: self()],
          rooms: ["room-1"],
          emit: "jido.chat.message.received",
          dispatch: {:pid, target: self()}
        ],
        options
      )

    sensor = start_supervised!({Sensor, opts})
    assert_receive {:source_started, worker, "push-client"}
    {sensor, worker, client}
  end

  defp fact(client, id, room \\ "room-1") do
    Jido.Chat.Signal.Policy.new!(
      Jido.Chat.Signal.MessageReceived,
      %{
        "item_id" => id,
        "delivery_id" => "batch",
        "room_id" => room,
        "message_id" => id,
        "text" => "hello",
        "sender" => %{"id" => "human"}
      },
      source: client.source
    )
  end

  test "push workers use the same admission and duplicate boundary as polling" do
    {sensor, worker, client} = start()
    signal = fact(client, "one")
    assert :ok = GenServer.call(worker, {:batch, [signal]})
    assert_receive {:signal, ^signal}
    assert :ok = GenServer.call(worker, {:batch, [signal]})
    refute_receive {:signal, _}
    assert {:error, :invalid_push} = Sensor.push(sensor, :bad)
    send(sensor, :poll)
    assert :sys.get_state(sensor).timer == nil
    assert Process.alive?(worker)
  end

  test "a Sensor captures its catalog once before input admission" do
    client = Client.new!(CountingAdapter, id: "push-client")
    Process.register(self(), CountingAdapter)
    {sensor, _worker, ^client} = start(client: client)
    assert_receive :definitions_read
    signal = fact(client, "one")

    assert :ok = Sensor.push(sensor, [signal])
    assert_receive {:signal, ^signal}
    assert :ok = Sensor.push(sensor, [signal])
    refute_receive :definitions_read
    refute_receive {:signal, _}
  end

  test "large identities use bounded duplicate memory and keep type separation" do
    {sensor, _worker, client} = start(emit: ["jido.chat.message.received", "jido.chat.message.updated"])

    for index <- 1..8 do
      signal = fact(client, String.duplicate("x", 120_000) <> to_string(index))
      assert :ok = Sensor.push(sensor, [signal])
      assert_receive {:signal, ^signal}
      assert :ok = Sensor.push(sensor, [signal])
    end

    seen = :sys.get_state(sensor).seen
    assert MapSet.size(seen) == 8
    assert :erlang.external_size(seen) < 2_000
    refute_receive {:signal, _}

    original = fact(client, String.duplicate("x", 120_000) <> "1")
    changed = Jido.Chat.Signal.Policy.new!(Jido.Chat.Signal.MessageUpdated, original.data, source: client.source)
    assert :ok = Sensor.push(sensor, [changed])
    assert_receive {:signal, ^changed}
  end

  test "worker exit reports do not expose private reasons or Source options" do
    secret = Base.encode64(:crypto.strong_rand_bytes(24))
    {sensor, worker, _client} = start(options: [observer: self(), private_option: secret])
    ref = Process.monitor(sensor)

    status = :sys.get_status(sensor)
    refute inspect(status) =~ secret

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        Process.exit(worker, {:private_provider_error, secret})
        assert_receive {:DOWN, ^ref, :process, ^sensor, {:source_exit, :source_failure}}
        assert_receive {:source_started, replacement, "push-client"}
        assert Process.alive?(replacement)
      end)

    refute log =~ secret
  end

  test "push filtering rejects foreign and malformed facts, and skips unselected rooms and types" do
    {sensor, worker, client} = start()
    signal = fact(client, "one")

    for invalid <- [%{signal | source: "foreign"}, %{signal | data: %{}}, :bad] do
      assert {:error, :input_rejected} = Sensor.push(sensor, [invalid])
    end

    assert :ok =
             GenServer.call(
               worker,
               {:batch, [fact(client, "two", "other"), %{signal | type: "jido.chat.message.updated"}]}
             )

    refute_receive {:signal, _}
  end

  test "push rejects invalid Chat context and size before Dispatch" do
    {sensor, _worker, client} = start()
    signal = fact(client, "one")

    for invalid <- [
          %{signal | extensions: %{"correlationid" => "unapproved"}},
          %{signal | data: Map.put(signal.data, "text", String.duplicate("x", 262_144))}
        ] do
      assert {:error, :input_rejected} = Sensor.push(sensor, [invalid])
    end

    refute_receive {:signal, _}
  end

  test "room filters use the provider schema's validated data" do
    client = Client.new!(Jido.Chat.PluginFixture.ProviderAdapter, id: "push-client")
    {sensor, _worker, ^client} = start(client: client, emit: "test.chat.room.changed")

    signal =
      Jido.Chat.PluginFixture.RoomChanged.new!(
        %{"item_id" => "one", "delivery_id" => "batch", "room_id" => "room-1"},
        source: client.source
      )

    raw = %{signal | data: Map.put(signal.data, "room_id", "room-1")}
    assert :ok = Sensor.push(sensor, [raw])
    refute_receive {:signal, _}
  end

  test "a rejected push batch can be retried without repeating its accepted prefix" do
    store = start_supervised!({Agent, fn -> [true, false, true] end})
    {sensor, _worker, client} = start(dispatch: {__MODULE__.Dispatch, store: store, observer: self()})
    batch = [fact(client, "one"), fact(client, "two")]
    assert {:error, :input_rejected} = Sensor.push(sensor, batch)
    assert_receive {:accepted, %{data: %{"item_id" => "one"}}}
    assert :ok = Sensor.push(sensor, batch)
    assert_receive {:accepted, %{data: %{"item_id" => "two"}}}
    refute_receive {:accepted, _}
  end

  test "Sensor shutdown stops its linked source worker" do
    {_sensor, worker, _client} = start()
    ref = Process.monitor(worker)
    stop_supervised(Sensor)
    assert_receive {:DOWN, ^ref, :process, ^worker, :shutdown}
  end

  test "Sensor shutdown stops a plain source worker that traps exits" do
    {_sensor, worker, _client} = start(source: TrappingSource)
    on_exit(fn -> if Process.alive?(worker), do: Process.exit(worker, :kill) end)
    ref = Process.monitor(worker)
    stop_supervised(Sensor)
    assert_receive :source_ignored_shutdown
    assert_receive {:DOWN, ^ref, :process, ^worker, :killed}, 2_000
  end

  test "a failed source causes Sensor restart under its host supervisor" do
    {sensor, worker, _} = start()
    ref = Process.monitor(sensor)
    Process.exit(worker, :kill)
    assert_receive {:DOWN, ^ref, :process, ^sensor, {:source_exit, :killed}}
    assert_receive {:source_started, replacement, "push-client"}
    refute replacement == worker
  end

  test "source mode callbacks are checked and failed startup is returned" do
    refute Sensor.valid_source?(InvalidSource)
    refute Sensor.valid_source?(nil)
    refute Sensor.valid_source?(String)
    Process.flag(:trap_exit, true)
    client = Client.new!(Jido.Chat.PluginFixture.Adapter, id: "failed")

    assert {:error, :source_start_failed} =
             Sensor.start_link(
               client: client,
               source: FailedSource,
               emit: "jido.chat.message.received",
               dispatch: {:pid, target: self()}
             )
  end

  test "a list selects disjoint input families without admitting unselected facts" do
    {sensor, worker, client} = start(emit: ["jido.chat.message.received", "jido.chat.message.updated"])
    original = fact(client, "list")

    changed =
      Jido.Chat.Signal.Policy.new!(Jido.Chat.Signal.MessageUpdated, Map.put(original.data, "item_id", "changed"),
        source: client.source
      )

    assert :ok = GenServer.call(worker, {:batch, [original, changed]})
    assert_receive {:signal, ^original}
    assert_receive {:signal, ^changed}
    assert %{process: :running, provider: :input_observed} = Sensor.status(sensor)
  end
end
