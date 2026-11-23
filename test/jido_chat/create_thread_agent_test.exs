defmodule Jido.Chat.CreateThreadAgentTest do
  use ExUnit.Case, async: false
  @moduletag capture_log: true

  alias Jido.Chat.CreateThread
  alias Jido.Chat.Operations.Definition
  alias Jido.Chat.Plugin.{Deliver, Execute}
  alias Jido.Chat.Signal.Schemas

  defmodule ProviderRequest do
    use Jido.Signal,
      type: "test.chat.command.create_thread",
      default_source: "urn:test:provider",
      schema:
        Schemas.object(%{
          "client_id" => Schemas.id(),
          "request_id" => Schemas.id(),
          "room_id" => Schemas.id() |> Jido.Joi.transform({__MODULE__, :normalize_room, []}),
          "name" => Jido.Joi.string()
        })

    def normalize_room(value, _opts), do: String.upcase(value)
  end

  defmodule ProviderCompleted do
    use Jido.Signal, Definition.completion_options(ProviderRequest, Schemas.result(:created_thread))
  end

  defmodule ProviderFailed do
    use Jido.Signal, Definition.failure_options(ProviderRequest)
  end

  defmodule ProviderAction do
    use Jido.Action,
      name: "provider_create_thread",
      schema: ProviderRequest.schema(),
      output_schema: ProviderCompleted.schema()

    @definition %Definition{
      action: __MODULE__,
      request: ProviderRequest,
      completed: ProviderCompleted,
      failed: ProviderFailed,
      result_schema: Schemas.result(:created_thread)
    }

    def definition, do: @definition
    @impl Jido.Action
    def run(params, context), do: Definition.run(@definition, params, context)
  end

  defmodule Adapter do
    use Jido.Chat.Adapter
    def channel_type, do: :test
    def capabilities, do: %{create_thread: :native}
    def operation_definitions, do: [ProviderAction.definition()]
    def normalize(_, _, _), do: {:error, :unused}

    def invoke(client, request, _opts) do
      server = Jido.whereis_agent(Jido.Chat.CreateThreadAgentTest.Jido, "thread-agent")
      snapshot = Jido.AgentServer.snapshot(server)
      send(Jido.Chat.CreateThreadAgentTest, {:provider, snapshot.agent_revision, request})

      client.config[:result] ||
        {:ok, %{"id" => "thread-1", "room_id" => request.data["room_id"], "name" => request.data["name"]}}
    end
  end

  defmodule AlternateFailure do
    use Jido.Signal,
        ProviderRequest
        |> Definition.failure_options()
        |> Keyword.put(:type, "test.chat.command.create_thread.alternate_failure")
  end

  defmodule AlternateAdapter do
    use Jido.Chat.Adapter
    defdelegate channel_type(), to: Adapter
    defdelegate capabilities(), to: Adapter
    defdelegate invoke(client, signal, opts), to: Adapter
    defdelegate normalize(client, input, opts), to: Adapter

    def operation_definitions, do: [%{ProviderAction.definition() | failed: AlternateFailure}]
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
    use Jido.Agent, name: "thread_agent", plugins: [Jido.Chat.Plugin]

    state do
      schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
    end

    chat do
      connection :support do
        client Jido.Chat.CreateThreadAgentTest.Adapter, id: "support"
        rooms ["room-1"]
        commands [Jido.Chat.CreateThread, Jido.Chat.CreateThreadAgentTest.ProviderAction]
      end
    end

    routes do
      route "jido.chat.command.create_thread", Jido.Chat.Plugin.Execute
      route "jido.chat.command.create_thread.completed", Jido.Chat.CreateThreadAgentTest.Record
      route "jido.chat.command.create_thread.failed", Jido.Chat.CreateThreadAgentTest.Record
      route "test.chat.command.create_thread", Jido.Chat.Plugin.Execute
      route "test.chat.command.create_thread.failed", Jido.Chat.CreateThreadAgentTest.Record
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
    [plugin] = definition.plugins
    [connection] = plugin.data.connections
    connection = put_in(connection.client.config, result: opts[:result])

    connections =
      if opts[:alternate] do
        alternate = %{
          connection
          | name: :alternate,
            client: %{connection.client | id: "alternate", adapter: AlternateAdapter}
        }

        [alternate, connection]
      else
        [connection]
      end

    definition = put_in(definition.plugins, [%{plugin | data: %{plugin.data | connections: connections}}])

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
    assert CreateThread.schema() == Jido.Chat.Signal.CreateThread.schema()
    assert CreateThread.output_schema() == CreateThread.Completed.schema()
    assert CreateThread.Completed.type() == "jido.chat.command.create_thread.completed"

    assert CreateThread.Completed.dataschema() ==
             "urn:jido:chat:schema:command_create_thread:1:completed"

    assert {:ok, data} = CreateThread.validate_params(request.data)
    assert data == request.data
    assert {:error, _} = CreateThread.validate_params(Map.put(data, "name", 42))
  end

  test "a normalized room denial uses the configured client failure Signal" do
    server = start(alternate: true)
    normalized = ProviderRequest.new!(request().data)
    assert normalized.data["room_id"] == "ROOM-1"
    raw = %{normalized | data: %{normalized.data | "room_id" => "room-1"}}

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} = Jido.AgentServer.call(server, raw)
    assert_receive {:thread_result, %Jido.Signal{type: "test.chat.command.create_thread.failed", data: failed}}
    assert failed["code"] == "forbidden"
    assert failed["outcome"] == "not_attempted"
    refute_received {:provider, _, _}
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

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed, effects: :pending}} =
             Jido.AgentServer.call(server, request)

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
    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} = Jido.AgentServer.call(server, request)
    assert_receive {:provider, 1, _}, 2_000
    assert_receive {:thread_result, reply}, 2_000
    assert reply.type == CreateThread.Failed.type()
    assert reply.data["code"] == "forbidden"
    assert reply.data["outcome"] == "rejected"
    assert Jido.Signal.get_context(reply, "jidocausationid") == request.id
  end

  test "a failed state commit prevents provider execution" do
    server = start(reject: true)
    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed}} = Jido.AgentServer.call(server, request())
    assert Jido.AgentServer.snapshot(server).agent_revision == 0
    refute_received {:provider, _, _}
    refute_received {:thread_result, _}
  end
end
