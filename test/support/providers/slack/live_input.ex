defmodule Jido.Chat.Slack.LiveInput do
  @moduledoc false
  import ExUnit.Assertions
  import ExUnit.Callbacks, only: [start_supervised: 1]
  alias __MODULE__.ReplaySocket
  alias Jido.Chat
  alias Jido.Chat.Signal
  alias Jido.Chat.Slack.{LiveAPI, LiveFixture, Source}

  @replay_token "slack-replay-sentinel"

  def receive_message(ctx) do
    with :ok <- connect(ctx, Signal.MessageReceived.type()) do
      text = LiveAPI.marker(ctx, "Socket Mode receive")
      room = ctx.room_id
      {sent, _} = LiveAPI.post(ctx, text)
      id = sent["id"]
      type = Signal.MessageReceived.type()

      receive do
        {:signal, %{type: ^type, data: %{"room_id" => ^room, "message_id" => ^id, "text" => ^text}} = fact} ->
          assert :ok = Chat.AdapterTestKit.Assertions.assert_json_round_trip(fact, Chat.catalog(ctx.client))
      after
        15_000 ->
          {:blocked, "Slack sent no matching Socket Mode event; check the message subscription and test app connection"}
      end
    end
  end

  def replayed_interaction(ctx) do
    room = ctx.room_id
    {id, value} = button(ctx)
    replay = %{ctx.client | credentials: %{app_token: @replay_token}, config: []}

    start_sensor(
      replay,
      room,
      [
        Signal.ActionReceived.type(),
        Signal.ModalSubmitted.type(),
        Signal.SlashCommandReceived.type()
      ],
      open_client: ReplaySocket,
      socket_client: ReplaySocket,
      socket_client_opts: [observer: self()]
    )

    assert_receive {:slack_replay_connected, worker, socket}, 2_000

    private = %{
      "trigger_id" => "replay-private-trigger",
      "response_url" => "https://slack-replay.invalid/private",
      "user" => %{"id" => "UREPLAY"}
    }

    replay(
      worker,
      socket,
      "interactive",
      Map.merge(private, %{
        "type" => "block_actions",
        "channel" => %{"id" => room},
        "message" => %{"ts" => id},
        "actions" => [%{"type" => "button", "action_id" => value, "value" => value}]
      })
    )

    fact = receive_action(ctx, id, value, 2_000)
    assert fact.data["actor_id"] == "UREPLAY"
    assert_private_fields_absent(fact)

    replay(
      worker,
      socket,
      "interactive",
      Map.merge(private, %{
        "type" => "view_submission",
        "view" => %{
          "id" => "VREPLAY",
          "callback_id" => "jido-proof",
          "private_metadata" => Jason.encode!(%{"room_id" => room}),
          "state" => %{
            "values" => %{"answer" => %{"input" => %{"type" => "plain_text_input", "value" => "jido-proof"}}}
          }
        }
      })
    )

    modal_type = Signal.ModalSubmitted.type()

    assert_receive {:signal,
                    %{
                      type: ^modal_type,
                      data: %{
                        "room_id" => ^room,
                        "callback_id" => "jido-proof",
                        "values" => %{"answer.input" => "jido-proof"}
                      }
                    } = modal}

    assert_private_fields_absent(modal)

    replay(
      worker,
      socket,
      "slash_commands",
      Map.merge(private, %{
        "channel_id" => room,
        "command" => "/jido-proof",
        "text" => ctx.run_id,
        "user_id" => "UREPLAY"
      })
    )

    slash_type = Signal.SlashCommandReceived.type()
    assert_receive {:signal, %{type: ^slash_type, data: %{"room_id" => ^room, "command" => "/jido-proof"}} = slash}
    assert slash.data["text"] == ctx.run_id
    assert_private_fields_absent(slash)

    LiveAPI.edit_and_check_removal(ctx, id, LiveAPI.marker(ctx, "Slack action verified"))
  end

  def live_interaction(ctx) do
    with :ok <- connect(ctx, Signal.ActionReceived.type()) do
      {id, value} = button(ctx)
      IO.puts("SLACK_UI_READY Click Verify Jido SDK in the test channel (#{ctx.run_id})")
      _ = receive_action(ctx, id, value, 180_000)
      LiveAPI.edit_and_check_removal(ctx, id, LiveAPI.marker(ctx, "Slack action verified"))
    end
  end

  defp button(ctx) do
    value = "jido:verify:#{ctx.run_id}"
    text = LiveAPI.marker(ctx, "Slack interaction check")
    {sent, _} = LiveAPI.post(ctx, text, :public, %{"keyboard" => LiveAPI.keyboard(value)})
    LiveAPI.assert_button(LiveAPI.stored(ctx, sent["id"]), value)
    {sent["id"], value}
  end

  defp receive_action(ctx, id, value, timeout) do
    type = Signal.ActionReceived.type()
    room = ctx.room_id

    assert_receive {:signal,
                    %{
                      type: ^type,
                      data: %{"room_id" => ^room, "message_id" => ^id, "action_id" => ^value, "value" => ^value}
                    } = fact},
                   timeout

    assert :ok = Chat.AdapterTestKit.Assertions.assert_json_round_trip(fact, Chat.catalog(ctx.client))
    fact
  end

  defp assert_private_fields_absent(fact) do
    assert {:ok, encoded} = Jido.Signal.Codec.serialize(fact)
    refute encoded =~ "replay-private-trigger"
    refute encoded =~ "slack-replay.invalid"
  end

  defp connect(ctx, type) do
    sensor =
      start_sensor(ctx.client, ctx.room_id, type,
        open_client_opts: [req: LiveFixture.Request],
        socket_client_opts: [async: false, handle_initial_conn_failure: false]
      )

    worker = :sys.get_state(sensor).worker
    wait_for_socket(worker, System.monotonic_time(:millisecond) + 10_000)
  end

  defp wait_for_socket(worker, deadline) do
    case :sys.get_state(worker, 15_000).socket do
      socket when is_pid(socket) ->
        :ok

      _ ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(50)
          wait_for_socket(worker, deadline)
        else
          {:blocked, "Slack Socket Mode connection did not open; check the test app token and connections:write access"}
        end
    end
  end

  defp start_sensor(client, room, emit, options) do
    result =
      start_supervised(
        {Chat.Sensor,
         client: client, source: Source, emit: emit, rooms: [room], dispatch: {:pid, target: self()}, options: options}
      )

    case result do
      {:ok, sensor} ->
        sensor

      {:error, {reason, _child}} when reason in [:invalid_sensor_options, :source_start_failed] ->
        IO.puts("Slack test Sensor startup failed (#{reason})")
        flunk("Slack test Sensor startup failed")

      {:error, _} ->
        flunk("Slack test Sensor startup failed")
    end
  end

  defp replay(worker, socket, type, payload) do
    id = "replay-#{System.unique_integer([:positive])}"

    frame =
      Jason.encode!(%{"envelope_id" => id, "type" => type, "payload" => payload, "accepts_response_payload" => true})

    send(worker, {:socket_mode, socket, {:text, frame}})
    assert_receive {:slack_replay_ack, ack}
    assert Jason.decode!(ack) == %{"envelope_id" => id}
  end

  defmodule ReplaySocket do
    @moduledoc false
    @behaviour Jido.Chat.Slack.SocketMode.Client
    @behaviour Jido.Chat.Slack.SocketMode.SocketClient

    @impl true
    def open_socket("slack-replay-sentinel", _), do: {:ok, "wss://slack-replay.invalid"}
    def open_socket(_, _), do: {:error, :invalid_replay}

    @impl true
    def connect("wss://slack-replay.invalid", owner, opts) do
      observer = Keyword.fetch!(opts, :observer)
      socket = {observer, make_ref()}
      send(observer, {:slack_replay_connected, owner, socket})
      {:ok, socket}
    end

    @impl true
    def send_text({observer, _}, payload) do
      send(observer, {:slack_replay_ack, payload})
      :ok
    end

    @impl true
    def close(_), do: :ok
  end
end
