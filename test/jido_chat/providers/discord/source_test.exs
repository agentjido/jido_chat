defmodule Jido.Chat.Discord.SourceTest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true
  import Jido.Chat.Discord.Fixtures
  alias Jido.Chat.Discord.{GatewayWorker, Source, TestGateway}

  defp start_source(extra \\ []) do
    c =
      client(fn _, :get, "/gateway/bot", nil -> {:ok, %{"url" => "wss://gateway.example"}} end,
        token: "token-#{System.unique_integer([:positive])}",
        config: [transport_observer: self()]
      )

    opts = [
      client: c,
      source: Source,
      emit: "jido.chat.message.received",
      rooms: ["202"],
      dispatch: {:pid, target: self()},
      options: [gateway: TestGateway, test_pid: self(), reconnect_delay: 1]
    ]

    opts = Keyword.merge(opts, extra)
    sensor = start_supervised!({Jido.Chat.Sensor, opts})
    assert_receive {:discord_transport_options, private}
    refute Keyword.has_key?(private, :token)
    refute Keyword.has_key?(private, :credentials)
    assert_receive {:gateway_open, worker, connection, _}
    send(worker, {:gateway_up, connection})
    :sys.get_state(worker)
    send(worker, {:gateway_upgrade, connection, connection})
    packet(worker, connection, %{"op" => 10, "d" => %{"heartbeat_interval" => 100_000}})
    assert_receive {:gateway_sent, %{"op" => 2, "d" => %{"intents" => 46593}}}

    packet(worker, connection, %{
      "op" => 0,
      "t" => "READY",
      "s" => 1,
      "d" => %{"session_id" => "session", "resume_gateway_url" => "wss://resume.example", "user" => %{"id" => "bot"}}
    })

    {sensor, worker, connection, c}
  end

  defp packet(worker, connection, data) do
    send(worker, {:gateway_ws, connection, connection, {:text, Jason.encode!(data)}})
    :sys.get_state(worker)
  end

  test "Source declares concrete facts and hashes its credential identity" do
    c = client()
    assert Source.mode() == :push
    assert Source.signal_types() == Enum.map(Jido.Chat.Discord.event_definitions(), & &1.type())
    assert Source.key(c, []) == :crypto.hash(:sha256, "test-secret")
    assert Source.key(%{c | credentials: %{}}, []) == nil
    assert Source.key(%{c | credentials: %{token: ""}}, []) == nil
    assert {:error, :missing_token} = Source.start_link(%{c | credentials: %{}}, self(), [])
    assert {:error, :missing_token} = Source.start_link(%{c | credentials: %{token: ""}}, self(), [])
  end

  test "shared Sensor admits, filters and deduplicates Gateway facts" do
    {sensor, worker, con, c} = start_source()
    event = %{"op" => 0, "t" => "MESSAGE_CREATE", "s" => 2, "d" => message()}
    packet(worker, con, event)
    assert_receive {:signal, %Jido.Signal{data: %{"text" => "hello"}}}
    packet(worker, con, event)
    refute_receive {:signal, _}, 20
    packet(worker, con, put_in(event, ["d", "channel_id"], "outside"))
    refute_receive {:signal, _}, 20
    packet(worker, con, %{event | "t" => "MESSAGE_DELETE"})
    refute_receive {:signal, _}, 20
    assert Process.alive?(sensor)
    refute inspect(:sys.get_status(worker)) =~ c.credentials.token
    ref = Process.monitor(worker)
    GenServer.stop(sensor)
    assert_receive {:DOWN, ^ref, :process, ^worker, _}
    assert_receive {:gateway_closed, ^con}
  end

  test "heartbeats, server requests and missing ACK trigger session resume" do
    {_, worker, con, _} = start_source()
    packet(worker, con, %{"op" => 11})
    packet(worker, con, %{"op" => 1})
    assert_receive {:gateway_sent, %{"op" => 1, "d" => 1}}
    send(worker, {:heartbeat, con})
    :sys.get_state(worker)
    assert_receive {:gateway_sent, %{"op" => 1}}
    send(worker, {:heartbeat, con})
    assert_receive {:gateway_closed, ^con}
    assert_receive {:gateway_open, ^worker, con2, "wss://resume.example"}
    send(worker, {:gateway_up, con2})
    :sys.get_state(worker)
    packet(worker, con2, %{"op" => 10, "d" => %{"heartbeat_interval" => 100_000}})
    assert_receive {:gateway_sent, %{"op" => 6, "d" => %{"session_id" => "session", "seq" => 1}}}
    packet(worker, con2, %{"op" => 0, "t" => "RESUMED", "s" => 5, "d" => %{}})
    assert :sys.get_state(worker).sequence == 5
  end

  test "server reconnect and invalid sessions reset identity when required" do
    {_, worker, con, _} = start_source()
    packet(worker, con, %{"op" => 9, "d" => false})
    assert_receive {:gateway_open, ^worker, con2, "wss://gateway.example"}
    send(worker, {:gateway_up, con2})
    :sys.get_state(worker)
    packet(worker, con2, %{"op" => 10, "d" => %{"heartbeat_interval" => 100_000}})
    assert_receive {:gateway_sent, %{"op" => 2}}
    packet(worker, con2, %{"op" => 7})
    assert_receive {:gateway_closed, ^con2}
    assert_receive {:gateway_open, ^worker, _, _}
  end

  test "thread parent input makes room filtering work" do
    {_, worker, con, _} = start_source()

    packet(worker, con, %{
      "op" => 0,
      "t" => "GUILD_CREATE",
      "s" => 2,
      "d" => %{"threads" => [%{"id" => "thread", "parent_id" => "202"}]}
    })

    packet(worker, con, %{"op" => 0, "t" => "MESSAGE_CREATE", "s" => 3, "d" => message(%{"channel_id" => "thread"})})
    assert_receive {:signal, %{data: %{"room_id" => "202", "thread_id" => "thread"}}}

    packet(worker, con, %{
      "op" => 0,
      "t" => "THREAD_CREATE",
      "s" => 4,
      "d" => %{"id" => "thread2", "parent_id" => "202", "name" => "new"}
    })

    assert :sys.get_state(worker).parents["thread2"] == "202"
  end

  test "fatal close codes stop the Source and Sensor" do
    {sensor, worker, con, _} = start_source()
    ref = Process.monitor(sensor)
    send(worker, {:gateway_ws, con, con, {:close, 4014, "not allowed"}})
    assert_receive {:DOWN, ^ref, :process, ^sensor, _}, 1000
    assert_receive {:gateway_closed, ^con}
  end

  test "unknown messages and stale sockets have no effect" do
    {_, worker, con, _} = start_source()
    packet(worker, con, %{"op" => 99})
    send(worker, {:gateway_down, self(), :closed})
    send(worker, :unrelated)
    assert :sys.get_state(worker).connection == con

    assert GatewayWorker.format_status(%{state: "secret", message: "private"}) == %{
             state: :redacted,
             message: :redacted,
             log: :redacted,
             dictionary: :redacted
           }
  end

  test "network errors, disconnects, and malformed JSON reconnect" do
    for kind <- [:down, :error, :connection_error, :exit, :close, :expired, :invalid_sequence, :timeout, :json] do
      {_sensor, worker, con, _} = start_source()

      event =
        case kind do
          :down -> {:gateway_down, con, :closed}
          :error -> {:gateway_error, con, :closed}
          :connection_error -> {:gateway_error, con, :closed}
          :exit -> {:EXIT, con, :closed}
          :close -> {:gateway_ws, con, con, :close}
          :expired -> {:gateway_ws, con, con, {:close, 4009, "expired"}}
          :invalid_sequence -> {:gateway_ws, con, con, {:close, 4007, "bad sequence"}}
          :timeout -> {:connect_timeout, con}
          :json -> {:gateway_ws, con, con, {:text, "invalid"}}
        end

      send(worker, event)
      assert_receive {:gateway_closed, ^con}
      assert_receive {:gateway_open, ^worker, _, _}
      stop_supervised(Jido.Chat.Sensor)
    end
  end

  test "a resumable invalid session keeps its session" do
    {_, worker, con, _} = start_source()
    packet(worker, con, %{"op" => 9, "d" => true})
    assert_receive {:gateway_open, ^worker, _, "wss://resume.example"}
  end

  test "normal Gateway close reconnects" do
    {_, worker, con, _} = start_source()
    send(worker, {:gateway_ws, con, con, {:close, 1000, "closed"}})
    assert_receive {:gateway_open, ^worker, _, _}
  end

  test "a rejected Sensor batch stops without advancing the session" do
    Process.flag(:trap_exit, true)
    test = self()

    sensor =
      spawn(fn ->
        receive do
          {:"$gen_call", from, {:push, _}} ->
            send(test, :batch_rejected)
            GenServer.reply(from, {:error, :input_rejected})
        end
      end)

    c = client(fn _, _, _, _ -> {:ok, %{"url" => "wss://example"}} end)
    {:ok, worker} = Source.start_link(c, sensor, gateway: TestGateway, test_pid: self())
    ref = Process.monitor(worker)
    assert_receive {:gateway_open, ^worker, con, _}
    send(worker, {:gateway_up, con})
    :sys.get_state(worker)

    send(
      worker,
      {:gateway_ws, con, con, {:text, Jason.encode!(%{"op" => 0, "t" => "MESSAGE_CREATE", "s" => 2, "d" => message()})}}
    )

    assert_receive :batch_rejected
    assert_receive {:DOWN, ^ref, :process, ^worker, :input_rejected}
    assert_receive {:gateway_closed, ^con}
  end

  test "discovery failure retries and authorization failure stops" do
    Process.flag(:trap_exit, true)
    c = client(fn _, _, _, _ -> {:error, :offline} end)
    {:ok, worker} = Source.start_link(c, self(), gateway: TestGateway, test_pid: self(), reconnect_delay: 100_000)
    state = :sys.get_state(worker)
    assert state.retry == 1
    send(worker, {:heartbeat, nil})
    assert :sys.get_state(worker).connection == nil
    GenServer.stop(worker)
    c = client(fn _, _, _, _ -> {:error, {:rejected, :unauthorized, %{}}} end)
    {:ok, worker} = Source.start_link(c, self(), [])
    ref = Process.monitor(worker)
    assert_receive {:DOWN, ^ref, :process, ^worker, :unauthorized}
  end

  test "Source stops when its Sensor dies" do
    sensor =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    c = client(fn _, _, _, _ -> {:ok, %{"url" => "wss://example"}} end)
    {:ok, worker} = Source.start_link(c, sensor, gateway: TestGateway, test_pid: self())
    assert_receive {:gateway_open, ^worker, con, _}
    ref = Process.monitor(worker)
    send(sensor, :stop)
    assert_receive {:DOWN, ^ref, :process, ^worker, :normal}
    assert_receive {:gateway_closed, ^con}
  end
end
