defmodule Jido.Chat.PluginAccessTest do
  use ExUnit.Case, async: false

  defmodule HostIdentity do
    @behaviour Jido.Chat.IdentityProvider

    @impl true
    def resolve(%{provider: "mock", account_id: "secure/client", external_id: external_id}, _context) do
      case external_id do
        "external-human" -> {:ok, %{id: "host-human", kind: :human, assurance: :verified}}
        "external-denied" -> {:ok, %{id: "host-denied", kind: :human, assurance: :verified}}
        _other -> {:error, :identity_not_found}
      end
    end

    def resolve(_source, _context), do: {:error, :identity_scope_denied}
  end

  defmodule HostAuthorizer do
    @behaviour Jido.Chat.Authorizer

    @impl true
    def authorize(%{id: "host-human"}, :message_receive, %{id: "room-1"}, _context), do: :ok
    def authorize(_principal, _action, _resource, _context), do: {:error, :not_authorized}
  end

  defmodule RecordPrincipal do
    use Jido.Action, name: "record_chat_principal", schema: Jido.Joi.map()

    @impl true
    def run(_params, context) do
      {:ok, %{context.agent_state | principal_id: context.chat.principal.id}}
    end
  end

  defmodule SecuredAgent do
    use Jido.Agent, name: "secured_chat_agent", plugins: [Jido.Chat.Plugin]

    state do
      schema Jido.Joi.object(%{principal_id: Jido.Joi.string() |> Jido.Joi.default("")})
    end

    chat do
      identity_provider(HostIdentity)
      authorizer(HostAuthorizer)

      connection :secure do
        client Jido.Chat.PluginFixture.Adapter, id: "secure/client"
        rooms ["room-1"]
      end
    end

    routes do
      route("jido.chat.message.received", RecordPrincipal)
    end
  end

  setup do
    {:ok, _} = Application.ensure_all_started(:jido)
    jido = __MODULE__.Jido
    start_supervised!({Jido, name: jido, namespace: "chat-plugin-access-test"})
    {:ok, server} = Jido.start_agent(jido, SecuredAgent, id: "secured")
    assert :ok = Jido.AgentServer.await_ready(server)
    connection = hd(Jido.Chat.Plugin.connections(server))
    %{jido: jido, server: server, connection: connection}
  end

  test "configured ingress exposes only the host-resolved Principal", context do
    signal = fact(context.connection.client, "external-human")

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.Chat.Plugin.ingest(context.server, :secure, signal)

    assert Jido.AgentServer.snapshot(context.server).agent.state.principal_id == "host-human"
  end

  test "unknown and unauthorized external actors do not reach the Agent", context do
    assert {:error, :identity_not_found} =
             Jido.Chat.Plugin.ingest(context.server, :secure, fact(context.connection.client, "unknown"))

    assert {:error, :not_authorized} =
             Jido.Chat.Plugin.ingest(
               context.server,
               :secure,
               fact(context.connection.client, "external-denied")
             )

    assert Jido.AgentServer.snapshot(context.server).agent.state.principal_id == ""
  end

  test "a direct AgentServer call cannot bypass configured ingress admission", context do
    signal = fact(context.connection.client, "external-human", id: "direct-bypass")
    principal = Jido.Chat.Principal.new(%{id: "host-human", kind: :human, assurance: :verified})

    result =
      Jido.AgentServer.call(context.server, signal,
        context: %{
          chat: %{
            connection: :secure,
            client_id: context.connection.client.id,
            adapter: context.connection.client.adapter,
            principal: principal
          }
        }
      )

    assert match?({:error, _}, result) or
             match?({:ok, %Jido.AgentServer.TurnResult{status: :failed}}, result)

    assert Jido.AgentServer.snapshot(context.server).agent.state.principal_id == ""
  end

  test "application configuration supplies the Agent access modules", context do
    keys = [:identity_provider, :identity_options, :authorizer, :authorization_options]
    previous = Map.new(keys, &{&1, Application.fetch_env(:jido_chat, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:jido_chat, key, value)
        {key, :error} -> Application.delete_env(:jido_chat, key)
      end)
    end)

    Application.put_env(:jido_chat, :identity_provider, HostIdentity)
    Application.put_env(:jido_chat, :identity_options, %{})
    Application.put_env(:jido_chat, :authorizer, HostAuthorizer)
    Application.put_env(:jido_chat, :authorization_options, %{})

    {:ok, server} =
      Jido.start_agent(context.jido, Jido.Chat.PluginFixture.Agent, id: "application-configured")

    assert :ok = Jido.AgentServer.await_ready(server)
    access = Jido.Chat.Plugin.Runtime.access(server)
    assert access.identity_provider == HostIdentity
    assert access.authorizer == HostAuthorizer
  end

  defp fact(client, external_id, opts \\ []) do
    Jido.Chat.Signal.Policy.new!(
      Jido.Chat.Signal.MessageReceived,
      %{
        "item_id" => Keyword.get(opts, :id, "item:" <> external_id),
        "delivery_id" => "delivery:" <> external_id,
        "message_id" => "message:" <> external_id,
        "room_id" => "room-1",
        "sender" => %{"id" => external_id},
        "text" => "Hello"
      },
      source: client.source,
      id: Keyword.get(opts, :id, "signal:" <> external_id)
    )
  end
end
