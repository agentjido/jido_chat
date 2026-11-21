defmodule Jido.Chat.Discord.LiveUITest do
  use ExUnit.Case, async: false
  alias Jido.Chat.Discord.LiveHelpers, as: L
  alias Jido.Chat.Discord.{LiveInteractionAgent, LiveInteractionHost, Source}
  @moduletag :live
  @moduletag :live_ui
  @moduletag capture_log: true
  @moduletag timeout: 600_000
  unless System.get_env("RUN_LIVE_DISCORD_UI") == "true" do
    @moduletag skip: "set RUN_LIVE_DISCORD_UI=true and use Discord UI in the authorized test channel"
  end

  test "fresh UI button modal and slash travel through Source Sensor Agent Chat and provider" do
    %{client: c, room: room, guild: guild} = L.setup_target()
    {:ok, bot} = L.wire(c, :get, "/users/@me")
    c = %{c | config: [bot_id: bot["id"]]}
    host = start_supervised!({LiveInteractionHost, {c, self()}})
    {:ok, _} = Application.ensure_all_started(:jido)
    start_supervised!({Jido, name: Jido.Chat.Discord.UIJido})
    definition = LiveInteractionAgent.definition()
    [entry] = definition.plugins
    [connection] = entry.data.connections
    source = %{connection.source | options: [interaction_sink: {LiveInteractionHost, :put, [LiveInteractionHost]}]}

    connection = %{
      connection
      | client: Map.take(c, [:adapter, :id, :credentials, :config, :transport]),
        rooms: [room],
        source: source
    }

    definition = %{definition | plugins: [%{entry | data: %{entry.data | connections: [connection]}}]}
    {:ok, server} = Jido.start_agent(Jido.Chat.Discord.UIJido, definition, id: "discord-ui-proof")
    assert :ok = Jido.AgentServer.await_ready(server)
    on_exit(fn -> if Process.alive?(server), do: Jido.stop_agent(Jido.Chat.Discord.UIJido, server) end)
    wait_gateway(c, 300)
    command_name = "jido-proof-" <> Integer.to_string(System.unique_integer([:positive]))
    path = "/applications/#{bot["id"]}/guilds/#{guild}/commands"

    assert {:ok, command} =
             L.wire(c, :post, path, %{
               "name" => command_name,
               "description" => "Disposable Jido contract proof",
               "type" => 1
             })

    on_exit(fn -> assert {:ok, _} = L.wire(c, :delete, path <> "/" <> command["id"]) end)

    message =
      L.execute(c, Jido.Chat.Discord.Signal.SendRichMessage, %{
        "room_id" => room,
        "text" => "Jido live UI contract proof",
        "components" => [
          %{
            "type" => 1,
            "components" => [
              %{"type" => 2, "style" => 1, "label" => "Jido callback proof", "custom_id" => "jido:callback"},
              %{"type" => 2, "style" => 1, "label" => "Jido modal proof", "custom_id" => "jido:modal"}
            ]
          }
        ]
      })

    on_exit(fn -> L.remove_message(c, room, message["id"]) end)
    IO.puts("UI_READY message=#{message["id"]} slash=/#{command_name}")

    for expected <- [:callback, :modal_open, :modal_submit, :slash] do
      assert_receive {:interaction_result, fact, request, {:ok, completed}, elapsed}, 120_000
      assert elapsed >= 0 and elapsed < 3_000
      L.complete({:ok, completed}, c, request)
      assert completed.extensions["jidocausationid"] == request.id
      assert {:ok, _} = Jido.Signal.Catalog.validate(Jido.Chat.catalog(c), fact)

      case expected do
        :callback ->
          assert fact.data["action_id"] == "jido:callback"
          stored = L.execute(c, Jido.Chat.Signal.FetchMessage, %{"room_id" => room, "message_id" => message["id"]})
          assert stored["text"] == "Jido callback proof passed"

        :modal_open ->
          assert fact.data["action_id"] == "jido:modal"

        :modal_submit ->
          assert fact.type == "jido.chat.modal.submitted"
          assert fact.data["values"] == %{"answer" => "jido-ui-proof"}

        :slash ->
          assert fact.data["command"] == "/" <> command_name
      end

      refute inspect(Jido.AgentServer.snapshot(server).agent.state) =~ "token"
      IO.puts("UI_PASS #{expected} interaction=#{fact.data["interaction_id"]} response_ms=#{elapsed}")
    end

    assert :sys.get_state(host).controls == %{}
    :ok = Jido.stop_agent(Jido.Chat.Discord.UIJido, server)
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
end
