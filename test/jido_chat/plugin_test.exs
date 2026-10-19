defmodule Jido.Chat.PluginTest do
  use ExUnit.Case, async: false
  @moduletag capture_log: true

  # This adapter has no Telegram dependency and performs no network calls.
  setup do
    {:ok, _} = Application.ensure_all_started(:jido)
    Process.register(self(), __MODULE__)

    start_supervised!({Jido, name: Jido.Chat.PluginTest.Jido})
    :ok
  end

  defp start(opts \\ []) do
    client =
      Jido.Chat.Client.new!(Keyword.get(opts, :adapter, Jido.Chat.PluginFixture.Adapter),
        id: "mock/support",
        config: [observer: __MODULE__, result: opts[:result]]
      )

    original = Jido.Chat.PluginFixture.Agent.definition()
    [entry] = original.extensions
    [connection] = entry.data.connections

    connection = %{
      connection
      | client: Map.take(client, [:adapter, :id, :credentials, :config, :transport]),
        rooms: Keyword.get(opts, :rooms, ["room-1"]),
        source: opts[:source]
    }

    routes =
      Enum.reject(Keyword.get(opts, :routes, original.routes), &(&1.path in Keyword.get(opts, :remove_routes, [])))

    definition = %{
      original
      | extensions: [%{entry | data: %{entry.data | connections: [connection]}}],
        routes: routes
    }

    # No custom startup or dispatch option.
    {:ok, server} =
      Jido.start_agent(Jido.Chat.PluginTest.Jido, definition, id: "mock-test", partition: opts[:partition])

    :ok = Jido.AgentServer.await_ready(server)

    %{
      server: server,
      connection: hd(Jido.Chat.Plugin.connections(server)),
      client: client,
      definition: definition
    }
  end

  defp fact(client, changes \\ %{}) do
    data =
      Map.merge(
        %{
          "item_id" => "mock:item:1",
          "delivery_id" => "mock:delivery:1",
          "message_id" => "human-message",
          "room_id" => "room-1",
          "sender" => %{"id" => "human", "is_bot" => false},
          "text" => "/spike mock boundary"
        },
        changes
      )

    Jido.Chat.Signal.MessageReceived.new!(data, source: client.source)
  end

  defp delivery(server, type, tries \\ 200)
  defp delivery(_server, _type, 0), do: flunk("result did not reach the Agent")

  defp delivery(server, type, tries) do
    agent = Jido.AgentServer.agent(server)

    if agent.state.last_delivery == type do
      agent
    else
      Process.sleep(10)
      delivery(server, type, tries - 1)
    end
  end

  test "results return to the same Agent partition" do
    default = start()
    tenant = start(partition: "tenant")

    assert {:ok, _, _} = Jido.Chat.Plugin.ingest(tenant.server, tenant.connection.name, fact(tenant.client))
    assert_receive {:mock_send, "mock/support", _command}, 2_000
    assert delivery(tenant.server, "jido.chat.command.send_message.completed").state.last_request == "mock:item:1:reply"
    assert Jido.AgentServer.agent(default.server).state.last_delivery == ""
  end

  test "incoming facts reject invalid Chat context and size before an Agent turn" do
    ctx = start()
    signal = fact(ctx.client)

    for invalid <- [
          %{signal | extensions: %{"correlationid" => "unapproved"}},
          %{signal | data: Map.put(signal.data, "text", String.duplicate("x", 262_144))}
        ] do
      assert {:error, _} = Jido.Chat.Plugin.ingest(ctx.server, ctx.connection.name, invalid)
    end

    assert Jido.AgentServer.agent(ctx.server).state.replies == 0
    refute_receive {:mock_send, _, _}
  end

  test "a webhook connection admits declared provider facts without a Sensor" do
    routes = Jido.Chat.PluginFixture.Agent.definition().routes

    custom = %{
      hd(routes)
      | path: "test.chat.room.changed",
        handler: %{kind: :action, target: Jido.Chat.PluginFixture.Accept},
        emits: []
    }

    ctx = start(adapter: Jido.Chat.PluginFixture.ProviderAdapter, rooms: ["ROOM-1"], routes: [custom | routes])

    signal =
      Jido.Chat.PluginFixture.RoomChanged.new!(
        %{"item_id" => "one", "delivery_id" => "batch", "room_id" => "room-1"},
        source: ctx.client.source
      )

    assert {:ok, _, []} = Jido.Chat.Plugin.ingest(ctx.server, ctx.connection.name, signal)
    refute_receive {:mock_send, _, _}
  end

  test "room scope applies after a provider schema transforms the incoming data" do
    ctx = start(adapter: Jido.Chat.PluginFixture.ProviderAdapter)

    signal =
      Jido.Chat.PluginFixture.RoomChanged.new!(
        %{"item_id" => "one", "delivery_id" => "batch", "room_id" => "room-1"},
        source: ctx.client.source
      )

    raw = %{signal | data: Map.put(signal.data, "room_id", "room-1")}
    assert {:error, :chat_scope_denied} = Jido.Chat.Plugin.ingest(ctx.server, ctx.connection.name, raw)
  end

  test "core facts use the unchanged reply Action and real Chat Action through a mock adapter" do
    ctx = start()
    incoming = fact(ctx.client, %{"thread_id" => "topic-1"})

    assert {:ok, committed, [%Jido.Agent.Directive.Emit{dispatch: nil, signal: emitted}]} =
             Jido.Chat.Plugin.ingest(ctx.server, ctx.connection.name, incoming)

    assert committed.state.replies == 1
    assert_receive {:mock_send, "mock/support", command}, 2_000
    assert command.id == emitted.id
    assert command.data["reply_to_id"] == "human-message"
    assert command.data["thread_id"] == "topic-1"
    assert command.data["text"] == "Spike received your message."
    assert command.extensions["causationid"] == incoming.id

    assert delivery(ctx.server, "jido.chat.command.send_message.completed").state.last_request ==
             "mock:item:1:reply"

    refute_receive {:mock_send, _, _}
  end

  test "edits and reactions use the same Plugin and core SDK Actions with a mock adapter" do
    ctx = start()
    assert {:ok, _, _} = Jido.Chat.Plugin.ingest(ctx.server, :telegram, fact(ctx.client))
    assert_receive {:mock_send, _, _}
    delivery(ctx.server, "jido.chat.command.send_message.completed")
    original = fact(ctx.client)

    edit =
      Jido.Chat.Signal.MessageUpdated.new!(Map.put(original.data, "item_id", "edit:1"),
        source: ctx.client.source
      )

    assert {:ok, _, _} = Jido.Chat.Plugin.ingest(ctx.server, :telegram, edit)
    assert_receive {:mock_send, _, %{type: "jido.chat.command.edit_message"} = command}, 2_000
    assert command.data["message_id"] == "mock-reply"
    assert command.extensions["causationid"] == edit.id
    delivery(ctx.server, "jido.chat.command.edit_message.completed")

    for {definition, operation, item} <- [
          {Jido.Chat.Signal.ReactionAdded, "add_reaction", "reaction:1"},
          {Jido.Chat.Signal.ReactionRemoved, "remove_reaction", "reaction:2"}
        ] do
      signal =
        definition.new!(
          %{
            "item_id" => item,
            "delivery_id" => item,
            "room_id" => "room-1",
            "message_id" => "mock-reply",
            "actor_id" => "human",
            "reaction" => "👍"
          },
          source: ctx.client.source
        )

      assert {:ok, _, _} = Jido.Chat.Plugin.ingest(ctx.server, :telegram, signal)
      type = "jido.chat.command." <> operation
      assert_receive {:mock_send, _, %{type: ^type} = reaction}, 2_000
      assert reaction.data["reaction"] == "👀"
      delivery(ctx.server, type <> ".completed")
    end

    refute_receive {:mock_send, _, _}
  end

  test "removing the input route blocks input before the Action runs" do
    ctx = start(remove_routes: ["jido.chat.message.received"])

    assert {:error, _} =
             Jido.Chat.Plugin.ingest(ctx.server, ctx.connection.name, fact(ctx.client))

    assert Jido.AgentServer.agent(ctx.server).state.replies == 0
    refute_receive {:mock_send, _, _}
  end

  test "removing the command route leaves the reply Action usable but prevents Chat I/O" do
    ctx = start(remove_routes: ["jido.chat.command.*"])

    assert {:ok, %{state: %{replies: 1}}, [%Jido.Agent.Directive.Emit{dispatch: nil}]} =
             Jido.Chat.Plugin.ingest(ctx.server, ctx.connection.name, fact(ctx.client))

    refute_receive {:mock_send, _, _}, 200
    assert Jido.AgentServer.agent(ctx.server).state.last_delivery == ""
  end

  test "a mock failure returns through its Plugin as a failure Signal" do
    ctx = start(result: {:error, :test_send_failure})

    assert {:ok, _, _} =
             Jido.Chat.Plugin.ingest(ctx.server, ctx.connection.name, fact(ctx.client))

    assert_receive {:mock_send, _, _}, 2_000
    assert delivery(ctx.server, "jido.chat.command.send_message.failed").state.replies == 1
    refute_receive {:mock_send, _, _}
  end

  test "a result cannot bypass a removed result route" do
    ctx = start(remove_routes: ["jido.chat.command.*.completed"])

    assert {:ok, _, _} =
             Jido.Chat.Plugin.ingest(ctx.server, ctx.connection.name, fact(ctx.client))

    assert_receive {:mock_send, _, _}, 2_000
    refute_receive {:mock_send, _, _}, 200
    assert Jido.AgentServer.agent(ctx.server).state.last_delivery == ""
  end

  test "the mock boundary rejects another source and a room outside its declared scope" do
    ctx = start()

    assert {:error, :chat_scope_denied} =
             Jido.Chat.Plugin.ingest(
               ctx.server,
               ctx.connection.name,
               fact(ctx.client, %{"room_id" => "other-room"})
             )

    assert {:error, :chat_scope_denied} =
             Jido.Chat.Plugin.ingest(ctx.server, ctx.connection.name, %{
               fact(ctx.client)
               | source: "urn:other:client"
             })

    refute_receive {:mock_send, _, _}
    assert Jido.AgentServer.agent(ctx.server).state.replies == 0
  end

  test "an undeclared connection is rejected without I/O" do
    ctx = start()

    assert {:error, :unknown_chat_connection} =
             Jido.Chat.Plugin.ingest(ctx.server, :missing, fact(ctx.client))

    refute_receive {:mock_send, _, _}
  end

  test "malformed input cannot reach the Reply Action" do
    ctx = start()
    message = fact(ctx.client)
    malformed = %{message | data: Map.put(message.data, "text", 123)}
    assert {:error, _} = Jido.Chat.Plugin.ingest(ctx.server, :telegram, malformed)
    refute_receive {:mock_send, _, _}
    assert Jido.AgentServer.agent(ctx.server).state.replies == 0
  end

  test "output rejects an unknown Client or an out-of-scope room without I/O" do
    ctx = start()

    [{_, root, _, _}] =
      Supervisor.which_children(Jido.agent_supervisor_name(Jido.Chat.PluginTest.Jido))

    {{:plugin, Jido.Chat.Plugin}, runtime, _, _} =
      Enum.find(Supervisor.which_children(root), &(elem(&1, 0) == {:plugin, Jido.Chat.Plugin}))

    context = %{jido: Jido.Chat.PluginTest.Jido, agent_id: "mock-test"}

    for {client_id, room_id, expected} <- [
          {"unknown-client", "room-1", :unknown_chat_client},
          {ctx.client.id, "other-room", :chat_scope_denied}
        ] do
      command =
        Jido.Chat.Signal.SendMessage.new!(%{
          "client_id" => client_id,
          "request_id" => "scope-probe",
          "room_id" => room_id,
          "text" => "must not send"
        })

      assert {:error, ^expected} =
               Jido.Chat.Plugin.dispatch(
                 runtime,
                 %Jido.Chat.Plugin.Deliver{signal: command},
                 context,
                 []
               )

      agent = delivery(ctx.server, "jido.chat.command.send_message.failed")
      assert agent.state.last_request == "scope-probe"
    end

    refute_receive {:mock_send, _, _}
  end

  test "the Agent runs against the unmodified V3 runtime with no topology edges" do
    ctx = start()
    assert ctx.definition.topology == %{agents: [], connections: []}
    source = Jido.AgentServer.TopologyRuntime.module_info(:compile)[:source] |> to_string()

    expected =
      Path.join(Mix.Project.deps_paths()[:jido], "lib/jido/agent_server/topology_runtime.ex")

    assert Path.expand(source) == Path.expand(expected)
    refute source =~ "/_core/"
    refute function_exported?(Jido.Chat.Plugin, :deliver_endpoint, 4)
    refute function_exported?(Jido.Chat.Plugin, :start_agent, 3)
  end

  test "the same Reply Action runs from a push worker through the owned Sensor" do
    ctx = start(source: %{module: Jido.Chat.PluginFixture.PushSource, options: [], emit: "jido.chat.message.received"})
    assert_receive {:push_worker, worker}
    assert :ok = GenServer.call(worker, {:batch, [fact(ctx.client)]})
    assert_receive {:mock_send, "mock/support", %{type: "jido.chat.command.send_message"}}, 2_000
    assert delivery(ctx.server, "jido.chat.command.send_message.completed").state.replies == 1
  end
end
