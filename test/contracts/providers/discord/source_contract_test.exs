defmodule Jido.Chat.Discord.SourceContractTest do
  use Covenant.Case, component: "jido_chat_discord.source", async: true
  import Jido.Chat.Discord.Fixtures
  import ExUnit.CaptureLog
  alias Jido.Chat.Discord.{Interaction, Source, TestGateway}

  def put(private, target, result) do
    send(target, {:private, private})

    case result do
      :hold ->
        receive do
          :release -> :ok
        end

      :raise ->
        raise private.token

      _ ->
        result
    end
  end

  defp connect(sink, dispatch \\ nil) do
    c = client(fn _, _, _, _ -> {:ok, %{"url" => "wss://gateway.example"}} end)

    options = [
      client: c,
      source: Source,
      options: [gateway: TestGateway, test_pid: self(), interaction_sink: sink],
      emit: "jido.chat.action.received",
      rooms: ["202"],
      dispatch: dispatch || {:pid, target: self()}
    ]

    _sensor = start_supervised!(Supervisor.child_spec({Jido.Chat.Sensor, options}, restart: :temporary))
    assert_receive {:gateway_open, worker, con, _}
    assert Process.alive?(worker)
    send(worker, {:gateway_up, con})
    :sys.get_state(worker)
    on_exit(fn -> if Process.alive?(worker), do: GenServer.stop(worker) end)
    {c, worker, con}
  end

  defp flush_gateway do
    receive do
      {:gateway_open, _, _, _} -> flush_gateway()
    after
      10 -> :ok
    end
  end

  defp event(secret),
    do: %{
      "op" => 0,
      "t" => "INTERACTION_CREATE",
      "s" => 2,
      "d" => %{
        "type" => 3,
        "id" => "909",
        "application_id" => "bot",
        "channel_id" => "202",
        "token" => secret,
        "member" => %{"user" => %{"id" => "404"}},
        "data" => %{"custom_id" => "proof"}
      }
    }

  @tag obligation: "jido_chat_discord.source.I1"
  test "Source identity and fact declarations have no startup side effects" do
    c = client()
    assert Source.mode() == :push
    assert Source.key(c, []) == :crypto.hash(:sha256, c.credentials.token)
    refute Source.key(c, []) == Source.key(%{c | credentials: %{token: "other"}}, [])
    assert length(Source.signal_types()) == 10
    assert "jido.chat.action.received" in Source.signal_types()
    assert {:error, :missing_token} = Source.start_link(%{c | credentials: %{}}, self(), [])
    assert Process.whereis(Jido) == nil
  end

  @tag obligation: "jido_chat_discord.source.I2"
  test "private sink runs before Signal admission and failure prevents admission" do
    Process.flag(:trap_exit, true)
    secret = Base.encode64(:crypto.strong_rand_bytes(24))

    for result <- [:hold, {:error, :rejected}, :raise] do
      {_c, worker, con} = connect({__MODULE__, :put, [self(), result]})
      ref = Process.monitor(worker)
      send(worker, {:gateway_ws, con, con, {:text, Jason.encode!(event(secret))}})

      assert_receive {:private,
                      %Interaction{
                        client_id: "discord-test",
                        bot_id: "bot",
                        room_id: "202",
                        interaction_id: "909",
                        token: ^secret
                      }}

      if result == :hold do
        refute_receive {:signal, _}, 20
        send(worker, :release)
        assert_receive {:signal, %{type: "jido.chat.action.received"}}
        GenServer.stop(worker)
      else
        assert_receive {:DOWN, ^ref, :process, ^worker, :input_rejected}
        refute_receive {:signal, _}, 20
      end

      stop_supervised(Jido.Chat.Sensor)
      flush_gateway()
    end
  end

  defmodule RejectSecond do
    @behaviour Jido.Signal.Dispatch.Adapter
    def options_schema, do: Zoi.keyword(store: Zoi.pid(), observer: Zoi.pid())

    def deliver(signal, opts) do
      Agent.get_and_update(opts[:store], fn
        0 ->
          send(opts[:observer], {:accepted, signal})
          {:ok, 1}

        n ->
          {{:error, :busy}, n}
      end)
    end
  end

  @tag obligation: "jido_chat_discord.source.I2"
  test "actual Sensor dispatch preserves an accepted prefix and stops on the next rejected event" do
    Process.flag(:trap_exit, true)
    store = start_supervised!({Agent, fn -> 0 end})
    {_c, worker, con} = connect(nil, {RejectSecond, store: store, observer: self()})
    secret = Base.encode64(:crypto.strong_rand_bytes(24))
    send(worker, {:gateway_ws, con, con, {:text, Jason.encode!(event(secret))}})
    assert_receive {:accepted, %{data: %{"interaction_id" => "909"}}}
    assert :sys.get_state(worker).sequence == 2
    ref = Process.monitor(worker)
    next = event(secret) |> put_in(["d", "id"], "910") |> Map.put("s", 3)
    send(worker, {:gateway_ws, con, con, {:text, Jason.encode!(next)}})
    assert_receive {:DOWN, ^ref, :process, ^worker, :input_rejected}
    assert_receive {:gateway_closed, ^con}
    refute_receive {:accepted, _}, 20
    assert Agent.get(store, & &1) == 1
  end

  @tag obligation: "jido_chat_discord.source.I3"
  test "private controls bind identities expire and reject before transport" do
    secret = Base.encode64(:crypto.strong_rand_bytes(24))
    c = client(fn _, _, _, _ -> flunk("invalid interaction reached transport") end)
    d = %{"room_id" => "202", "interaction_id" => "909"}
    now = System.monotonic_time(:millisecond)

    p = %Interaction{
      client_id: c.id,
      bot_id: "bot",
      room_id: "202",
      interaction_id: "909",
      token: secret,
      received_at: now
    }

    assert {:ok, ^secret} = Interaction.token(c, d, p)
    assert {:error, {:not_attempted, :invalid_interaction}} = Interaction.token(%{c | config: []}, d, p)
    refute inspect(p) =~ secret

    for changed <- [
          %{p | client_id: "other"},
          %{p | bot_id: "other"},
          %{p | room_id: "other"},
          %{p | interaction_id: "other"},
          %{p | received_at: now - 3_000},
          %{p | received_at: now + 10_000}
        ] do
      assert {:error, {:not_attempted, :invalid_interaction}} = Interaction.token(c, d, changed)
      signal = request(Jido.Chat.Discord.Signal.RespondInteraction, Map.merge(d, %{"response_type" => 4}))
      assert {:error, error} = Jido.Chat.execute(c, signal, options: [interaction: changed])
      refute inspect(error) =~ secret
    end

    assert {:error, :interaction_rejected} = Interaction.capture(c, event(secret)["d"], :invalid)

    assert {:error, :interaction_rejected} =
             Interaction.capture(
               c,
               put_in(event(secret)["d"], ["application_id"], "wrong"),
               {__MODULE__, :put, [self(), :ok]}
             )

    refute_receive {:private, _}, 20
  end

  @tag obligation: "jido_chat_discord.source.I4"
  test "controlled raw-input failure redacts OTP error report and closes socket" do
    Process.flag(:trap_exit, true)
    secret = Base.encode64(:crypto.strong_rand_bytes(24))
    {_c, worker, con} = connect({__MODULE__, :put, [self(), :raise]})
    ref = Process.monitor(worker)

    log =
      capture_log(fn ->
        send(worker, {:gateway_ws, con, con, {:text, Jason.encode!(event(secret))}})
        assert_receive {:DOWN, ^ref, :process, ^worker, :input_rejected}
        assert_receive {:gateway_closed, ^con}
      end)

    refute log =~ secret
    refute log =~ "test-secret"
    assert log =~ "input_rejected"

    task =
      Task.async(fn ->
        assert {:ok, _state} =
                 Jido.Chat.Discord.Gateway.init({self(), "wss://gateway.example", Mint.WebSocket})

        assert true == Process.flag(:sensitive, false)
      end)

    Task.await(task)
  end
end
