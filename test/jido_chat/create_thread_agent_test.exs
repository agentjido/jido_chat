defmodule Jido.Chat.CreateThreadAgentTest do
  use ExUnit.Case, async: false
  @moduletag capture_log: true

  alias Jido.Chat.CreateThread
  alias Jido.Chat.Plugin.{Deliver, Execute}

  defmodule Adapter do
    use Jido.Chat.Adapter
    def capabilities, do: %{create_thread: :native}
    def normalize(_, _, _), do: {:error, :unused}

    def invoke(client, request, _opts) do
      server = Jido.whereis_agent(Jido.Chat.CreateThreadAgentTest.Jido, "thread-agent")
      snapshot = Jido.AgentServer.snapshot(server)
      send(Jido.Chat.CreateThreadAgentTest, {:provider, snapshot.state_version, request})

      client.config[:result] ||
        {:ok, %{"id" => "thread-1", "room_id" => request.data["room_id"], "name" => request.data["name"]}}
    end
  end

  defmodule Record do
    use Jido.Action, name: "record_thread_result"

    def run(_data, context) do
      send(Jido.Chat.CreateThreadAgentTest, {:thread_result, context.signal})
      {:ok, context.agent_state}
    end
  end

  defmodule Reject do
    use Jido.Action, name: "reject_thread_state"

    def run(_data, context) do
      {:ok, %{count: :invalid}, [%Jido.Chat.Plugin.Deliver{signal: context.signal}]}
    end
  end

  defmodule Agent do
    use Jido.Agent, name: "thread_agent", extensions: [Jido.Chat.Plugin]

    agent do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    chat do
      connection :support do
        client Jido.Chat.CreateThreadAgentTest.Adapter, id: "support"
        rooms ["room-1"]
        commands [Jido.Chat.CreateThread]
      end
    end

    routes do
      route Jido.Chat.CreateThread, via: Jido.Chat.Plugin.Execute
      route "jido.chat.command.create_thread.completed", Jido.Chat.CreateThreadAgentTest.Record
      route "jido.chat.command.create_thread.failed", Jido.Chat.CreateThreadAgentTest.Record
    end
  end

  setup do
    {:ok, _} = Application.ensure_all_started(:jido)
    Process.register(self(), __MODULE__)
    start_supervised!({Jido, name: __MODULE__.Jido})
    :ok
  end

  defp request do
    CreateThread.new!(%{
      "client_id" => "support",
      "request_id" => "create-1",
      "room_id" => "room-1",
      "name" => "Support"
    })
  end

  defp start(opts \\ []) do
    definition = Agent.definition()
    [extension] = definition.extensions
    [connection] = extension.data.connections
    connection = put_in(connection.client.config, result: opts[:result])
    definition = put_in(definition.extensions, [%{extension | data: %{extension.data | connections: [connection]}}])

    definition =
      if opts[:reject] do
        [route | rest] = definition.routes
        %{definition | routes: [%{route | handler: %{kind: :action, target: Reject}} | rest]}
      else
        definition
      end

    {:ok, server} = Jido.start_agent(__MODULE__.Jido, definition, id: "thread-agent")
    :ok = Jido.AgentServer.await_ready(server)
    server
  end

  test "CreateThread uses one schema for Signal data and Action parameters" do
    request = request()
    assert Jido.SignalAction.defined?(CreateThread)
    assert CreateThread.schema() == Jido.Chat.Signal.CreateThread.schema()
    assert CreateThread.output_schema() == CreateThread.Completed.schema()
    assert CreateThread.__signal_action__().output.type == "jido.chat.command.create_thread.completed"

    assert CreateThread.__signal_action__().output.dataschema ==
             "urn:jido:chat:schema:command_create_thread:1:completed"

    assert {:ok, data} = CreateThread.validate_params(request.data)
    assert data == request.data
    assert {:error, _} = CreateThread.validate_params(Map.put(data, "name", 42))
  end

  test "the module route returns a directive without provider execution" do
    request = request()
    [route | _] = Agent.definition().routes
    assert route.path == CreateThread.type()
    assert route.handler == %{kind: :action, target: Execute}

    assert {:ok, %{state: %{count: 0}}, [%Deliver{signal: ^request}]} =
             Agent.cmd(Agent.instantiate!(id: "pure"), request)

    refute_received {:provider, _, _}
  end

  test "the provider sees the committed revision and its completion returns to the Agent" do
    server = start()
    request = request()
    assert {:ok, _, [%Deliver{}]} = Jido.AgentServer.call(server, request)
    assert_receive {:provider, 1, invoked}, 2_000
    assert invoked.id == request.id
    assert_receive {:thread_result, reply}, 2_000
    assert reply.type == CreateThread.Completed.type()
    assert reply.data["result"] == %{"id" => "thread-1", "room_id" => "room-1", "name" => "Support"}
    assert Jido.Signal.get_context(reply, "jidocausationid") == request.id
    assert {:ok, ^reply} = Jido.Signal.Catalog.validate(Jido.Chat.catalog(), reply)
  end

  test "provider failure returns a safe failure Signal after commit" do
    server = start(result: {:error, {:rejected, :forbidden}})
    request = request()
    assert {:ok, _, _} = Jido.AgentServer.call(server, request)
    assert_receive {:provider, 1, _}, 2_000
    assert_receive {:thread_result, reply}, 2_000
    assert reply.type == CreateThread.Failed.type()
    assert reply.data["code"] == "forbidden"
    assert reply.data["outcome"] == "rejected"
    assert Jido.Signal.get_context(reply, "jidocausationid") == request.id
  end

  test "a failed state commit prevents provider execution" do
    server = start(reject: true)
    assert {:error, _} = Jido.AgentServer.call(server, request())
    assert Jido.AgentServer.snapshot(server).state_version == 0
    refute_received {:provider, _, _}
    refute_received {:thread_result, _}
  end
end
