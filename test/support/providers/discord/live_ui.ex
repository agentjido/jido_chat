defmodule Jido.Chat.Discord.LiveUI do
  @moduledoc false
  import ExUnit.Assertions
  import ExUnit.Callbacks, only: [start_supervised!: 1]
  import Jido.Chat.LiveCase, only: [on_cleanup: 1]
  alias __MODULE__.ReplayTransport
  alias Jido.Chat
  alias Jido.Chat.Discord.LiveHelpers, as: L
  alias Jido.Chat.Discord.{LiveInteractionAgent, LiveInteractionHost, Source, TestGateway}
  alias Jido.Chat.Discord.Transport.REST

  @callback_id "jido:callback"
  @modal_button_id "jido:modal"

  def replayed(ctx) do
    %{client: client, room: room, message_id: message_id} = ctx = controls(ctx)
    assert Process.register(self(), __MODULE__.ReplayObserver)

    replay = %{
      client
      | credentials: %{token: ReplayTransport.token()},
        transport: ReplayTransport,
        config: [bot_id: client.config[:bot_id], replay_observer: self()]
    }

    {host, server} =
      start_pipeline(replay, room, ReplayTransport, gateway: TestGateway, test_pid: __MODULE__.ReplayObserver)

    gateway = start_replay_gateway(client.config[:bot_id])
    button = %{"type" => 3, "message" => %{"id" => message_id}}

    assert %{"content" => text} =
             replay_interaction(
               ctx,
               replay,
               server,
               gateway,
               2,
               7,
               Map.put(button, "data", %{"custom_id" => @callback_id, "component_type" => 2}),
               %{"action_id" => @callback_id, "message_id" => message_id}
             )

    assert %{"custom_id" => "jido:proof-modal" = modal_id} =
             replay_interaction(
               ctx,
               replay,
               server,
               gateway,
               3,
               9,
               Map.put(button, "data", %{"custom_id" => @modal_button_id, "component_type" => 2}),
               %{"action_id" => @modal_button_id, "message_id" => message_id}
             )

    assert %{"content" => "Jido modal proof passed", "flags" => 64} =
             replay_interaction(
               ctx,
               replay,
               server,
               gateway,
               4,
               4,
               %{
                 "type" => 5,
                 "data" => %{
                   "custom_id" => modal_id,
                   "components" => [%{"components" => [%{"custom_id" => "answer", "value" => "jido-ui-proof"}]}]
                 }
               },
               %{"callback_id" => modal_id, "values" => %{"answer" => "jido-ui-proof"}}
             )

    assert %{"content" => "Jido slash proof passed", "flags" => 64} =
             replay_interaction(
               ctx,
               replay,
               server,
               gateway,
               5,
               4,
               %{"type" => 2, "data" => %{"id" => ctx.command["id"], "name" => ctx.command["name"]}},
               %{"command" => "/" <> ctx.command["name"]}
             )

    assert text == "Jido callback proof passed"

    assert %{"id" => ^message_id, "text" => ^text} =
             Chat.edit_message(client, room, message_id, text, keyboard: %{"rows" => []}) |> L.complete(client)

    assert %{"content" => ^text, "components" => []} = L.raw_message(client, room, message_id)
    assert :sys.get_state(host).controls == %{}
    :ok = Jido.stop_agent(Jido.Chat.Discord.UIJido, server)
  end

  def interactions(ctx) do
    %{client: client, room: room, message_id: message_id, command: command} = controls(ctx)
    {host, server} = start_pipeline(client, room, REST, [])
    wait_gateway(client, 300)
    command_name = command["name"]
    IO.puts("UI_READY slash=/#{command_name}")

    for {expected, fields, response_type} <- [
          {:callback, %{"action_id" => @callback_id, "message_id" => message_id}, 7},
          {:modal_open, %{"action_id" => @modal_button_id, "message_id" => message_id}, 9},
          {:modal_submit, %{"callback_id" => "jido:proof-modal", "values" => %{"answer" => "jido-ui-proof"}}, 4},
          {:slash, %{"command" => "/" <> command_name}, 4}
        ] do
      {fact, request, elapsed} = assert_reply(client, server, room, fields, response_type, 120_000)
      assert fact.type == event_type(expected)

      if expected == :callback do
        assert %{"content" => "Jido callback proof passed"} = request.data["data"]
        assert %{"content" => "Jido callback proof passed"} = L.raw_message(client, room, message_id)
      end

      IO.puts("UI_PASS #{expected} response_ms=#{elapsed}")
    end

    assert :sys.get_state(host).controls == %{}
    :ok = Jido.stop_agent(Jido.Chat.Discord.UIJido, server)
  end

  defp controls(%{client: client, room: room, guild: guild} = ctx) do
    assert {:ok, %{"id" => bot_id}} = L.wire(client, :get, "/users/@me")
    client = %{client | config: Keyword.put(client.config, :bot_id, bot_id)}
    command_name = "jido-proof-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
    path = "/applications/#{bot_id}/guilds/#{guild}/commands"

    assert {:ok, %{"id" => command_id} = command} =
             L.wire(client, :post, path, %{
               "name" => command_name,
               "description" => "Disposable Jido contract proof",
               "type" => 1
             })

    on_cleanup(fn -> assert {:ok, _} = L.wire(client, :delete, path <> "/" <> command_id, nil, live_cleanup?: true) end)
    assert command["name"] == command_name
    assert command["type"] == 1

    text = "Jido live interaction check #{ctx.run_id}"

    message =
      L.execute(client, Jido.Chat.Discord.Signal.SendRichMessage, %{
        "room_id" => room,
        "text" => text,
        "components" => [
          %{
            "type" => 1,
            "components" => [
              %{"type" => 2, "style" => 1, "label" => "Jido callback proof", "custom_id" => @callback_id},
              %{"type" => 2, "style" => 1, "label" => "Jido modal proof", "custom_id" => @modal_button_id}
            ]
          }
        ]
      })

    L.track_message(client, room, message)
    message_id = message["id"]

    assert %{
             "content" => ^text,
             "components" => [%{"components" => [%{"custom_id" => @callback_id}, %{"custom_id" => @modal_button_id}]}]
           } = L.raw_message(client, room, message_id)

    Map.merge(ctx, %{client: client, command: command, message_id: message_id})
  end

  defp start_pipeline(client, room, transport, source_opts) do
    host = start_supervised!({LiveInteractionHost, {client, self()}})
    {:ok, _} = Application.ensure_all_started(:jido)
    start_supervised!({Jido, name: Jido.Chat.Discord.UIJido})
    definition = LiveInteractionAgent.definition()
    [entry] = definition.plugins
    [connection] = entry.data.connections
    source_opts = Keyword.put(source_opts, :interaction_sink, {LiveInteractionHost, :put, [LiveInteractionHost]})
    source = %{connection.source | options: source_opts}

    agent_client =
      client
      |> Map.take([:adapter, :id, :credentials])
      |> Map.merge(%{config: [bot_id: client.config[:bot_id]], transport: transport})

    connection = %{connection | client: agent_client, rooms: [room], source: source}
    definition = %{definition | plugins: [%{entry | data: %{entry.data | connections: [connection]}}]}
    assert {:ok, server} = Jido.start_agent(Jido.Chat.Discord.UIJido, definition, id: "discord-ui-proof")
    assert :ok = Jido.AgentServer.await_ready(server)
    on_cleanup(fn -> if Process.alive?(server), do: Jido.stop_agent(Jido.Chat.Discord.UIJido, server) end)
    {host, server}
  end

  defp start_replay_gateway(bot_id) do
    assert_receive {:gateway_open, worker, connection, "wss://discord-replay.invalid"}, 5_000
    send(worker, {:gateway_up, connection})
    gateway = {worker, connection}
    packet(gateway, %{"op" => 10, "d" => %{"heartbeat_interval" => 600_000}})
    assert_receive {:gateway_sent, %{"op" => 2}}, 5_000

    packet(gateway, %{
      "op" => 0,
      "t" => "READY",
      "s" => 1,
      "d" => %{"session_id" => "replay-session", "user" => %{"id" => bot_id}}
    })

    assert %{session: "replay-session"} = :sys.get_state(worker)
    gateway
  end

  defp replay_interaction(ctx, client, server, gateway, seq, response_type, data, fields) do
    id = Integer.to_string(seq)
    token = "replay-" <> id

    interaction =
      Map.merge(data, %{
        "id" => id,
        "application_id" => client.config[:bot_id],
        "channel_id" => ctx.room,
        "guild_id" => ctx.guild,
        "token" => token,
        "member" => %{"user" => %{"id" => "1"}}
      })

    packet(gateway, %{"op" => 0, "t" => "INTERACTION_CREATE", "s" => seq, "d" => interaction})
    {fact, request, _} = assert_reply(client, server, ctx.room, fields, response_type, 5_000)
    assert fact.type == event_type(data["type"])
    assert fact.data["interaction_id"] == id
    assert fact.data["actor_id"] == "1"
    refute Jason.encode!(Jido.Signal.Codec.to_map(fact)) =~ token
    refute inspect(Jido.AgentServer.snapshot(server).agent.state) =~ token

    response = request.data["data"]
    assert_receive {:discord_replay_ack, ^id, %{"type" => ^response_type, "data" => ^response}}
    refute_received {:discord_replay_ack, ^id, _}
    response
  end

  defp assert_reply(client, server, room, fields, response_type, timeout) do
    assert_receive {:interaction_result, fact, request, result, elapsed}, timeout
    assert elapsed >= 0 and elapsed < 3_000
    assert %{"acknowledged" => true} = L.complete(result, client, request)
    assert {:ok, _} = Jido.Signal.Catalog.validate(Jido.Chat.catalog(client), fact)
    assert fact.data["room_id"] == room
    assert Map.take(fact.data, Map.keys(fields)) == fields
    assert request.data["interaction_id"] == fact.data["interaction_id"]
    assert request.data["response_type"] == response_type
    refute inspect(Jido.AgentServer.snapshot(server).agent.state) =~ "token"
    {fact, request, elapsed}
  end

  defp event_type(kind) when kind in [3, :callback, :modal_open], do: Chat.Signal.ActionReceived.type()
  defp event_type(kind) when kind in [5, :modal_submit], do: Chat.Signal.ModalSubmitted.type()
  defp event_type(kind) when kind in [2, :slash], do: Chat.Signal.SlashCommandReceived.type()

  defp packet({worker, connection}, data) do
    send(worker, {:gateway_ws, connection, connection, {:text, Jason.encode!(data)}})
  end

  defp wait_gateway(c, attempts) do
    name = {Jido.Chat.Sensor, Source, Source.key(c, [])}
    pid = :global.whereis_name(name)
    ready = if is_pid(pid), do: :sys.get_state(:sys.get_state(pid).worker).session != nil, else: false

    unless ready do
      assert attempts > 0, "Gateway did not become ready"
      Process.sleep(100)
      wait_gateway(c, attempts - 1)
    end
  end

  defmodule ReplayTransport do
    @moduledoc false
    @behaviour Jido.Chat.Discord.Transport
    @token "discord-replay-sentinel"

    def token, do: @token

    @impl true
    def call(@token, :get, "/gateway/bot", nil, _), do: {:ok, %{"url" => "wss://discord-replay.invalid"}}

    def call(@token, :post, "/interactions/" <> route, body, opts) do
      with [id, "replay-" <> replay_id, "callback"] when id == replay_id <- String.split(route, "/"),
           observer when is_pid(observer) <- opts[:replay_observer] do
        send(observer, {:discord_replay_ack, id, body})
        {:ok, nil}
      else
        _ -> {:error, {:not_attempted, :invalid_replay}}
      end
    end

    def call(_, _, _, _, _), do: {:error, {:not_attempted, :invalid_replay}}
  end
end
