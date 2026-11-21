defmodule Jido.Chat.Slack.SourceTest do
  use ExUnit.Case, async: false

  alias Jido.Chat.Slack.{Adapter, SocketModeWorker, Source}

  defmodule OpenClient do
    @behaviour Jido.Chat.Slack.SocketMode.Client

    def open_socket(token, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:opened, token})
      {:ok, "wss://slack.example/socket"}
    end
  end

  defmodule SocketClient do
    @behaviour Jido.Chat.Slack.SocketMode.SocketClient

    def connect(url, owner, opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      socket = spawn_link(fn -> loop(test_pid) end)
      send(test_pid, {:connected, url, socket})
      send(owner, {:socket_mode, socket, :connected})
      {:ok, socket}
    end

    def send_text(socket, payload) do
      send(socket, {:sent, payload})
      :ok
    end

    def close(socket) do
      send(socket, :stop)
      :ok
    end

    defp loop(test_pid) do
      receive do
        {:sent, payload} ->
          send(test_pid, {:socket_sent, payload})
          loop(test_pid)

        :stop ->
          :ok
      end
    end
  end

  defmodule RejectSink do
    def emit(test_pid, payload, _opts) do
      send(test_pid, {:rejected, payload})
      {:error, :input_rejected}
    end
  end

  defp client(credentials \\ %{bot_token: "xoxb-test", app_token: "xapp-test"}) do
    Jido.Chat.Client.new!(Adapter,
      id: "slack-source-#{System.unique_integer([:positive])}",
      credentials: credentials,
      config: [bot_user_id: "UBOT"]
    )
  end

  test "Source declares facts, hashes source identity, and requires an app token" do
    value = client()
    assert Source.mode() == :push
    assert Source.signal_types() == Enum.map(Jido.Chat.Slack.event_definitions(), & &1.type())
    assert Source.key(value, []) == :crypto.hash(:sha256, "xapp-test")
    assert Source.key(%{value | credentials: %{}}, []) == nil
    assert {:error, :missing_app_token} = Source.start_link(%{value | credentials: %{}}, self(), [])
  end

  test "Socket Mode input is normalized, admitted, emitted, and then acknowledged" do
    value = client()

    sensor =
      start_supervised!(
        {Jido.Chat.Sensor,
         client: value,
         source: Source,
         emit: "jido.chat.message.received",
         dispatch: {:pid, target: self()},
         options: [
           open_client: OpenClient,
           open_client_opts: [test_pid: self()],
           socket_client: SocketClient,
           socket_client_opts: [test_pid: self()]
         ]}
      )

    assert_receive {:opened, "xapp-test"}
    assert_receive {:connected, "wss://slack.example/socket", socket}
    worker = :sys.get_state(sensor).worker

    envelope = %{
      "envelope_id" => "E1",
      "type" => "events_api",
      "payload" => %{
        "type" => "event_callback",
        "event" => %{"type" => "message", "channel" => "C1", "user" => "U1", "ts" => "1700000000.1", "text" => "hello"}
      }
    }

    send(worker, {:socket_mode, socket, {:text, Jason.encode!(envelope)}})
    assert_receive {:signal, %Jido.Signal{data: %{"text" => "hello"}}}
    assert_receive {:socket_sent, encoded}
    assert Jason.decode!(encoded) == %{"envelope_id" => "E1"}
  end

  test "worker does not acknowledge input that its sink rejects" do
    {:ok, worker} =
      SocketModeWorker.start_link(
        app_token: "xapp-test",
        sink_mfa: {RejectSink, :emit, [self()]},
        open_client: OpenClient,
        open_client_opts: [test_pid: self()],
        socket_client: SocketClient,
        socket_client_opts: [test_pid: self()]
      )

    assert_receive {:opened, "xapp-test"}
    assert_receive {:connected, _, socket}

    envelope = %{"envelope_id" => "E2", "type" => "events_api", "payload" => %{"type" => "unknown"}}
    send(worker, {:socket_mode, socket, {:text, Jason.encode!(envelope)}})
    assert_receive {:rejected, %{"type" => "unknown"}}
    refute_receive {:socket_sent, _}, 20
    refute inspect(:sys.get_status(worker)) =~ "xapp-test"
    GenServer.stop(worker)
  end

  test "worker includes an accepted interaction response and reconnects after a disconnect envelope" do
    {:ok, worker} =
      SocketModeWorker.start_link(
        app_token: "xapp-test",
        sink_mfa: {__MODULE__, :reply, [self()]},
        open_client: OpenClient,
        open_client_opts: [test_pid: self()],
        socket_client: SocketClient,
        socket_client_opts: [test_pid: self()],
        path_prefix: "actions"
      )

    assert_receive {:connected, _, socket}
    ref = Process.monitor(socket)

    envelope = %{
      "envelope_id" => "interaction",
      "type" => "Slash Commands",
      "accepts_response_payload" => true,
      "payload" => %{"text" => "hello"}
    }

    send(worker, {:socket_mode, socket, {:text, Jason.encode!(envelope)}})
    assert_receive {:sink_path, "/actions/slash_commands"}
    assert_receive {:socket_sent, encoded}
    assert Jason.decode!(encoded) == %{"envelope_id" => "interaction", "payload" => %{"text" => "Accepted"}}

    send(worker, {:socket_mode, socket, {:text, ~s({"type":"disconnect","envelope_id":"done"})}})
    assert_receive {:socket_sent, encoded}
    assert Jason.decode!(encoded) == %{"envelope_id" => "done"}
    assert_receive {:DOWN, ^ref, :process, ^socket, :normal}
    assert_receive {:connected, _, next_socket}
    assert next_socket != socket

    GenServer.stop(worker)
    SocketClient.close(next_socket)
  end

  def reply(test_pid, _payload, opts) do
    send(test_pid, {:sink_path, opts[:path]})
    {:reply, %{body: "Accepted"}}
  end
end
