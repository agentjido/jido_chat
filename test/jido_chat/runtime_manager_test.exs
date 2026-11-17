defmodule Jido.Chat.RuntimeManagerTest do
  use ExUnit.Case, async: false

  alias Jido.Chat.Runtime.Room
  alias Jido.Chat.Runtime.Storage.Memory
  alias Jido.Chat.Runtime.Supervisor, as: RuntimeSupervisor

  defmodule Adapter do
    use Jido.Chat.Adapter

    @impl true
    def channel_type, do: :test

    @impl true
    def capabilities, do: %{send_message: :native}

    @impl true
    def normalize(_client, _payload, _opts), do: {:error, :unused}

    @impl true
    def invoke(_client, _request, _opts), do: {:error, :unused}
  end

  defmodule Runtime do
    use Jido.Chat.Runtime, jido: Jido.Chat.RuntimeManagerTest.Jido
  end

  defmodule Team do
    use Jido.Chat.Runtime.Room, name: "managed_team"

    room do
      admin("operator")
      history_limit(10)
      member_limit(10)
    end
  end

  defmodule OtherTeam do
    use Jido.Chat.Runtime.Room, name: "other_managed_team"

    room do
      admin("operator")
      history_limit(10)
      member_limit(10)
    end
  end

  defmodule Account do
    use Jido.Agent,
      name: "managed_account",
      plugins: [Jido.Chat.Plugin]

    chat do
      connection :provider do
        client(Adapter, id: "managed/client", credentials: %{})
        rooms(["provider-room"])
        commands([Jido.Chat.SendMessage])
      end
    end
  end

  defmodule InvalidAccount do
    use Jido.Agent, name: "invalid_managed_account"
  end

  defmodule DurableAccount do
    use Jido.Agent,
      name: "durable_managed_account",
      plugins: [Jido.Chat.Plugin, Jido.Chat.Runtime.Bridge]

    chat do
      connection :provider do
        client(Adapter,
          id: "managed/durable",
          credentials: %{},
          config: [poll_interval: 100]
        )

        rooms([])
        commands([Jido.Chat.SendMessage])
      end
    end

    routes do
      route("jido.chat.message.received", Jido.Chat.Runtime.Actions.BridgeInbound)
      route("jido.chat.room.message", Jido.Chat.Runtime.Actions.BridgeOutbound)
      route("jido.chat.command.send_message", Jido.Chat.Plugin.Execute)
      route("jido.chat.command.send_message.completed", Jido.Chat.Runtime.Actions.BridgeResult)
      route("jido.chat.command.send_message.failed", Jido.Chat.Runtime.Actions.BridgeResult)
    end
  end

  defmodule NoBridgeAccount do
    use Jido.Agent,
      name: "managed_account_without_bridge",
      plugins: [Jido.Chat.Plugin]

    chat do
      connection :provider do
        client(Adapter, id: "managed/no-bridge", credentials: %{})
        rooms([])
        commands([Jido.Chat.SendMessage])
      end
    end
  end

  defmodule Resolver do
    @behaviour Jido.Chat.Runtime.SecretResolver

    @impl true
    def resolve(refs, context) do
      if observer = Process.whereis(Jido.Chat.RuntimeManagerTest.Observer) do
        send(observer, {:secret_resolution, refs, context})
      end

      case refs["token"] do
        "fail" -> {:error, :secret_missing}
        "raise" -> raise "resolver-private-error"
        _reference -> {:ok, %{token: "resolved-token"}}
      end
    end
  end

  defmodule DurableRuntime do
    use Jido.Chat.Runtime,
      jido: Jido.Chat.RuntimeManagerTest.Jido,
      storage: {Memory, Jido.Chat.RuntimeManagerTest.Storage},
      connection_definitions: %{
        "provider" => DurableAccount,
        "no-bridge" => NoBridgeAccount,
        "invalid" => InvalidAccount
      },
      secret_resolver: Resolver
  end

  defmodule RuntimeWithoutResolver do
    use Jido.Chat.Runtime,
      jido: Jido.Chat.RuntimeManagerTest.Jido,
      storage: {Memory, Jido.Chat.RuntimeManagerTest.Storage},
      connection_definitions: %{"provider" => DurableAccount}
  end

  defmodule ConnectionsOnlyStorage do
    use Jido.Chat.Runtime.Storage.Adapter,
      capabilities: [Jido.Chat.Runtime.Storage.Connections]

    @impl Jido.Chat.Runtime.Storage.Connections
    defdelegate insert_connection(resource, declaration), to: Memory

    @impl Jido.Chat.Runtime.Storage.Connections
    defdelegate get_connection(resource, account_id), to: Memory

    @impl Jido.Chat.Runtime.Storage.Connections
    defdelegate list_connections(resource), to: Memory

    @impl Jido.Chat.Runtime.Storage.Connections
    defdelegate update_connection(resource, account_id, revision, declaration), to: Memory
  end

  defmodule ConnectionsOnlyRuntime do
    use Jido.Chat.Runtime,
      jido: Jido.Chat.RuntimeManagerTest.Jido,
      storage: {Jido.Chat.RuntimeManagerTest.ConnectionsOnlyStorage, Jido.Chat.RuntimeManagerTest.Storage},
      connection_definitions: %{"provider" => Account}
  end

  setup do
    {:ok, _} = Application.ensure_all_started(:jido)

    start_supervised!(
      {Jido,
       name: Jido.Chat.RuntimeManagerTest.Jido,
       namespace: "chat-runtime-manager-test-#{System.unique_integer([:positive])}"}
    )

    start_supervised!({Memory, name: __MODULE__.Storage})
    Process.register(self(), __MODULE__.Observer)

    :ok
  end

  test "starts declared Rooms and provider accounts below the host Jido instance" do
    start_runtime(
      rooms: [{"team", Team}],
      connections: [{"support", Account}]
    )

    assert {:ok,
            %{
              ready: true,
              healthy: true,
              rooms: [%{id: "team", state: :running, pid: room, ref: room_ref}],
              connections: [%{id: "support", state: :running, pid: account}]
            }} = Runtime.runtime_status()

    assert Process.alive?(room)
    assert Process.alive?(account)
    assert {:ok, ^room} = Jido.resolve_agent(Runtime.jido(), room_ref)
    assert {:ok, account_ref} = Runtime.connection_ref("support")
    assert {:ok, ^account} = Jido.resolve_agent(Runtime.jido(), account_ref)

    runtime_supervisor = Process.whereis(RuntimeSupervisor.supervisor_name(Runtime))
    manager = Process.whereis(RuntimeSupervisor.manager_name(Runtime))

    children = Supervisor.which_children(runtime_supervisor)
    assert length(children) == 2

    assert Enum.any?(children, fn {_id, pid, :worker, modules} ->
             pid == manager and Jido.Chat.Runtime.Manager in modules
           end)

    assert {:ok, bus} = Runtime.runtime_bus()
    assert Enum.any?(children, fn {_id, pid, :worker, modules} -> pid == bus and Jido.Signal.Bus in modules end)
    assert manager == Process.whereis(RuntimeSupervisor.manager_name(Runtime))
  end

  test "stops, starts, restarts, and lists a managed Room" do
    start_runtime(rooms: [{"team", Team}])

    assert {:ok, [%{id: "team", state: :running, pid: first, ref: ref}]} =
             Runtime.list_managed_rooms()

    assert {:ok, %{desired: :stopped, state: :stopped, pid: nil}} =
             Runtime.stop_managed_room("team")

    assert {:error, :not_found} = Jido.resolve_agent(Runtime.jido(), ref)
    assert {:ok, %{rooms: [%{state: :stopped}]}} = Runtime.reconcile_runtime()

    assert {:ok, %{desired: :running, state: :running, pid: second}} =
             Runtime.start_managed_room("team")

    refute second == first

    assert {:ok, %{state: :running, pid: third, ref: ref}} =
             Runtime.restart_managed_room("team")

    refute third == second
    assert ref.id == "team"
    assert {:ok, %{pid: ^third, state: :running}} = Runtime.room_runtime_status("team")
    assert {:error, :not_managed} = Runtime.start_managed_room("missing")
  end

  test "restores a required Agent that stops outside the manager" do
    start_runtime(rooms: [{"team", Team}])

    assert {:ok, %{pid: first, ref: ref}} = Runtime.room_runtime_status("team")
    assert :ok = Room.stop_agent(Runtime.jido(), ref)
    assert {:error, :not_found} = Jido.resolve_agent(Runtime.jido(), ref)

    assert {:ok, %{rooms: [%{pid: second, state: :running}]}} = Runtime.reconcile_runtime()
    refute first == second
  end

  test "periodic reconciliation restores a required Agent" do
    start_supervised!({Runtime, rooms: [{"team", Team}], reconcile_interval: 20})

    assert {:ok, %{pid: first, ref: ref}} = Runtime.room_runtime_status("team")
    assert :ok = Room.stop_agent(Runtime.jido(), ref)

    second = await_room_pid(first)
    refute first == second
    assert {:ok, ^second} = Jido.resolve_agent(Runtime.jido(), ref)
  end

  test "ignores a stale reconcile timer generation" do
    start_supervised!({Runtime, rooms: [{"team", Team}], reconcile_interval: 5_000})
    manager = Process.whereis(RuntimeSupervisor.manager_name(Runtime))

    %{reconcile_timer: current_timer} = :sys.get_state(manager)
    send(manager, {:reconcile, make_ref()})
    _ = :sys.get_state(manager)

    assert %{reconcile_timer: ^current_timer} = :sys.get_state(manager)
  end

  test "stops, starts, and restarts a managed provider account" do
    start_runtime(connections: [{"support", Account}])

    assert {:ok, [%{id: "support", state: :running, pid: first, ref: ref}]} =
             Runtime.list_managed_connections()

    assert {:ok, %{desired: :stopped, state: :stopped, pid: nil}} =
             Runtime.stop_managed_connection("support")

    assert {:error, :not_found} = Jido.resolve_agent(Runtime.jido(), ref)

    assert {:ok, %{desired: :running, state: :running, pid: second}} =
             Runtime.start_managed_connection("support")

    refute second == first

    assert {:ok, %{state: :running, pid: third, ref: ^ref}} =
             Runtime.restart_managed_connection("support")

    refute third == second

    assert {:ok, %{pid: ^third, state: :running}} =
             Runtime.managed_connection_status("support")

    assert {:error, :not_managed} = Runtime.start_managed_connection("missing")
  end

  test "isolates an invalid account from a valid Room" do
    start_runtime(
      rooms: [{"team", Team}],
      connections: [{"broken", InvalidAccount}]
    )

    assert {:ok,
            %{
              ready: true,
              healthy: false,
              error_count: 1,
              rooms: [%{state: :running}],
              connections: [
                %{id: "broken", state: :error, error: :one_chat_connection_required}
              ]
            }} = Runtime.runtime_status()

    assert {:error, {:reconcile_failed, 1, %{rooms: [%{state: :running}]}}} =
             Runtime.reconcile_runtime()
  end

  test "does not adopt or stop a different Agent at a declared Address" do
    {:ok, ref} = Jido.agent_address(Runtime.jido(), "team")
    {:ok, foreign} = Room.start_agent(Runtime.jido(), ref, OtherTeam)
    :ok = Jido.AgentServer.await_ready(foreign)

    runtime = start_runtime(rooms: [{"team", Team}])

    assert {:ok, %{state: :error, error: :address_in_use, pid: nil}} =
             Runtime.room_runtime_status("team")

    assert {:error, {:lifecycle_failed, %{error: :address_in_use}}} =
             Runtime.stop_managed_room("team")

    assert :ok = stop_supervised(Runtime)
    refute Process.alive?(runtime)
    assert Process.alive?(foreign)
    assert {:ok, ^foreign} = Jido.resolve_agent(Runtime.jido(), ref)
  end

  test "adopts live Agents after an unexpected manager restart" do
    start_runtime(rooms: [{"team", Team}])

    assert {:ok, %{pid: room}} = Runtime.room_runtime_status("team")
    first_manager = Process.whereis(RuntimeSupervisor.manager_name(Runtime))
    Process.exit(first_manager, :kill)

    second_manager = await_new_manager(first_manager)
    refute second_manager == first_manager

    assert {:ok, %{pid: ^room, state: :running}} = Runtime.room_runtime_status("team")
    assert Process.alive?(room)
  end

  test "normal Runtime shutdown stops managed Agent activations" do
    runtime =
      start_runtime(
        rooms: [{"team", Team}],
        connections: [{"support", Account}]
      )

    assert {:ok, room_ref} = Jido.agent_address(Runtime.jido(), "team")
    assert {:ok, account_ref} = Runtime.connection_ref("support")

    assert :ok = stop_supervised(Runtime)
    refute Process.alive?(runtime)
    assert {:error, :not_found} = Jido.resolve_agent(Runtime.jido(), room_ref)
    assert {:error, :not_found} = Jido.resolve_agent(Runtime.jido(), account_ref)
  end

  test "direct connection APIs work when the managed tree is not started" do
    assert {:error, :runtime_not_started} = Runtime.runtime_status()
    assert {:error, :runtime_not_started} = Runtime.runtime_bus()
    assert {:error, :runtime_not_started} = Runtime.subscribe_runtime("**")
    assert {:ok, ref, account} = Runtime.start_connection("direct", Account)
    assert {:ok, ^account} = Jido.resolve_agent(Runtime.jido(), ref)
    assert :ok = Runtime.stop_connection("direct")
  end

  test "durable accounts resolve secrets, apply bindings, restart on revision, and retain stopped state" do
    start_durable_runtime()

    assert {:ok,
            %{
              declaration: %{account_id: "support", revision: 1},
              activation: {:ok, %{state: :running, pid: first}}
            }} =
             DurableRuntime.provision_connection("provider", %{
               account_id: "support",
               secret_refs: %{"token" => "vault://support"},
               settings: %{"poll_interval" => 200}
             })

    assert_receive {:secret_resolution, %{"token" => "vault://support"}, context}
    assert context.account_id == "support"
    assert context.definition_key == "provider"

    first_agent = agent_snapshot(first)
    first_chat = plugin(first_agent, Jido.Chat.Plugin)
    [first_connection] = first_chat.data.connections
    assert first_connection.client.credentials == %{token: "resolved-token"}
    assert first_connection.client.config[:poll_interval] == 200
    assert first_connection.rooms == []

    assert {:ok, stored} = DurableRuntime.get_connection_declaration("support")
    refute inspect(stored) =~ "resolved-token"

    assert {:ok,
            %{
              binding: %{external_room_id: "provider-b"},
              activation: {:ok, %{state: :running, pid: second}}
            }} =
             DurableRuntime.create_bridge_binding(%{
               account_id: "support",
               room_id: "team",
               external_room_id: "provider-b",
               direction: :both
             })

    refute second == first

    assert {:ok, %{activation: {:ok, %{state: :running, pid: third}}}} =
             DurableRuntime.create_bridge_binding(%{
               account_id: "support",
               room_id: "team",
               external_room_id: "provider-a",
               direction: :outbound
             })

    refute third == second
    third_agent = agent_snapshot(third)
    [third_connection] = plugin(third_agent, Jido.Chat.Plugin).data.connections
    assert third_connection.rooms == ["provider-a", "provider-b"]

    mappings = plugin(third_agent, Jido.Chat.Runtime.Bridge).data.mappings
    assert Enum.map(mappings, & &1.external_room) == ["provider-a", "provider-b"]
    assert Enum.map(mappings, & &1.room) == ["team", "team"]
    assert Enum.all?(mappings, &is_binary(&1.name))

    assert {:ok,
            %{
              declaration: %{revision: 2},
              activation: {:ok, %{state: :running, pid: fourth}}
            }} =
             DurableRuntime.update_connection_declaration("support", 1, %{
               settings: %{"poll_interval" => 250}
             })

    refute fourth == third
    [fourth_connection] = plugin(agent_snapshot(fourth), Jido.Chat.Plugin).data.connections
    assert fourth_connection.client.config[:poll_interval] == 250

    first_manager = Process.whereis(RuntimeSupervisor.manager_name(DurableRuntime))
    Process.exit(first_manager, :kill)
    _second_manager = await_new_runtime_manager(first_manager, DurableRuntime)

    assert {:ok, %{pid: ^fourth, state: :running}} =
             DurableRuntime.managed_connection_status("support")

    assert :ok = DurableRuntime.deprovision_connection("support")

    assert {:ok, %{desired: :stopped, revision: 3}} =
             DurableRuntime.get_connection_declaration("support")

    assert {:error, :not_found} =
             DurableRuntime.connection_ref("support")
             |> then(fn {:ok, ref} -> Jido.resolve_agent(DurableRuntime.jido(), ref) end)

    assert :ok = stop_supervised(DurableRuntime)
    start_durable_runtime()

    assert {:ok, %{desired: :stopped, state: :stopped, pid: nil}} =
             DurableRuntime.managed_connection_status("support")
  end

  test "durable declaration failures are isolated from valid accounts and Rooms" do
    for declaration <- [
          Jido.Chat.Runtime.Connection.Declaration.new!(%{
            account_id: "good",
            definition_key: "provider"
          }),
          Jido.Chat.Runtime.Connection.Declaration.new!(%{
            account_id: "resolver-fails",
            definition_key: "provider",
            secret_refs: %{"token" => "fail"}
          }),
          Jido.Chat.Runtime.Connection.Declaration.new!(%{
            account_id: "resolver-raises",
            definition_key: "provider",
            secret_refs: %{"token" => "raise"}
          }),
          Jido.Chat.Runtime.Connection.Declaration.new!(%{
            account_id: "unknown-setting",
            definition_key: "provider",
            settings: %{"module" => "not-allowed"}
          }),
          Jido.Chat.Runtime.Connection.Declaration.new!(%{
            account_id: "unknown",
            definition_key: "missing"
          }),
          Jido.Chat.Runtime.Connection.Declaration.new!(%{
            account_id: "invalid",
            definition_key: "invalid"
          })
        ] do
      assert {:ok, ^declaration} = Memory.insert_connection(__MODULE__.Storage, declaration)
    end

    start_durable_runtime()

    assert {:ok, %{state: :running, pid: good}} =
             DurableRuntime.managed_connection_status("good")

    assert Process.alive?(good)

    assert {:ok, %{state: :error, error: :secret_resolution_failed}} =
             DurableRuntime.managed_connection_status("resolver-fails")

    assert {:ok, %{state: :error, error: :secret_resolution_failed}} =
             DurableRuntime.managed_connection_status("resolver-raises")

    assert {:ok, %{state: :error, error: :unknown_provider_setting}} =
             DurableRuntime.managed_connection_status("unknown-setting")

    assert {:ok, %{state: :error, error: :unknown_connection_definition}} =
             DurableRuntime.managed_connection_status("unknown")

    assert {:ok, %{state: :error, error: :one_chat_connection_required}} =
             DurableRuntime.managed_connection_status("invalid")

    assert {:ok, %{state: :running}} = DurableRuntime.room_runtime_status("team")
  end

  test "secret references require a configured resolver" do
    declaration =
      Jido.Chat.Runtime.Connection.Declaration.new!(%{
        account_id: "missing-resolver",
        definition_key: "provider",
        secret_refs: %{"token" => "vault://missing"}
      })

    assert {:ok, ^declaration} = Memory.insert_connection(__MODULE__.Storage, declaration)

    start_supervised!({RuntimeWithoutResolver, reconcile_interval: :infinity})

    assert {:ok, %{state: :error, error: :secret_resolver_required}} =
             RuntimeWithoutResolver.managed_connection_status("missing-resolver")
  end

  test "durable APIs persist and return activation evidence before the Runtime starts" do
    assert {:error, :unknown_connection_definition} =
             DurableRuntime.provision_connection("missing", %{account_id: "unknown"})

    assert {:error, :invalid_connection_declaration} =
             DurableRuntime.provision_connection("provider", %{})

    assert {:ok, %{declaration: declaration, activation: :not_started}} =
             DurableRuntime.provision_connection("provider", %{account_id: "offline"})

    assert {:ok, ^declaration} = DurableRuntime.get_connection_declaration("offline")
    assert {:ok, [^declaration]} = DurableRuntime.list_connection_declarations()

    assert {:error, :connection_conflict} =
             DurableRuntime.update_connection_declaration("offline", 2, %{metadata: %{owner: "chat"}})

    assert {:ok, %{declaration: updated, activation: :not_started}} =
             DurableRuntime.update_connection_declaration("offline", 1, %{metadata: %{owner: "chat"}})

    assert updated.revision == 2

    assert {:error, :connection_not_found} =
             DurableRuntime.create_bridge_binding(%{
               account_id: "missing",
               room_id: "team",
               external_room_id: "provider-missing"
             })

    assert {:ok, %{binding: binding, activation: :not_started}} =
             DurableRuntime.create_bridge_binding(%{
               account_id: "offline",
               room_id: "team",
               external_room_id: "provider-room"
             })

    assert {:ok, ^binding} = DurableRuntime.get_bridge_binding("offline", "provider-room")
    assert {:ok, [^binding]} = DurableRuntime.list_bridge_bindings("offline")

    assert {:error, :binding_conflict} =
             DurableRuntime.update_bridge_binding("offline", "provider-room", 2, %{direction: :outbound})

    assert {:ok, %{binding: outbound, activation: :not_started}} =
             DurableRuntime.update_bridge_binding("offline", "provider-room", 1, %{
               direction: :outbound
             })

    assert outbound.revision == 2

    assert {:ok, %{binding: disabled, activation: :not_started}} =
             DurableRuntime.deprovision_bridge_binding("offline", "provider-room")

    refute disabled.enabled
    assert disabled.revision == 3

    assert {:error, :binding_not_found} =
             DurableRuntime.deprovision_bridge_binding("offline", "missing")

    assert :ok = DurableRuntime.deprovision_connection("offline")

    assert {:ok, %{desired: :stopped, revision: 3}} =
             DurableRuntime.get_connection_declaration("offline")

    assert {:error, :connection_not_found} = DurableRuntime.deprovision_connection("missing")
  end

  test "a connection-only adapter can run a durable account without bindings" do
    declaration =
      Jido.Chat.Runtime.Connection.Declaration.new!(%{
        account_id: "connection-only",
        definition_key: "provider"
      })

    assert {:ok, ^declaration} =
             ConnectionsOnlyStorage.insert_connection(__MODULE__.Storage, declaration)

    start_supervised!({ConnectionsOnlyRuntime, reconcile_interval: :infinity})

    assert {:ok, %{state: :running, error: nil}} =
             ConnectionsOnlyRuntime.managed_connection_status("connection-only")

    assert {:error, :unsupported_storage_capability} =
             ConnectionsOnlyRuntime.create_bridge_binding(%{
               account_id: "connection-only",
               room_id: "team",
               external_room_id: "provider-room"
             })
  end

  test "durable bindings require the trusted Bridge plugin" do
    start_supervised!({DurableRuntime, reconcile_interval: :infinity})

    assert {:ok, %{activation: {:ok, %{state: :running}}}} =
             DurableRuntime.provision_connection("no-bridge", %{account_id: "plain"})

    assert {:ok, %{activation: {:ok, %{state: :error, error: :bridge_plugin_required}}}} =
             DurableRuntime.create_bridge_binding(%{
               account_id: "plain",
               room_id: "team",
               external_room_id: "provider-room"
             })
  end

  defp start_runtime(opts) do
    start_supervised!({Runtime, Keyword.put_new(opts, :reconcile_interval, :infinity)})
  end

  defp start_durable_runtime do
    start_supervised!({DurableRuntime, rooms: [{"team", Team}], reconcile_interval: :infinity})
  end

  defp agent_snapshot(server) do
    %Jido.AgentServer.Snapshot{agent: agent} = Jido.AgentServer.snapshot(server)
    agent
  end

  defp plugin(agent, provider), do: Enum.find(agent.plugins, &(&1.provider == provider))

  defp await_new_manager(first_manager, attempts \\ 100)

  defp await_new_manager(_first_manager, 0), do: flunk("manager did not restart")

  defp await_new_manager(first_manager, attempts) do
    case Process.whereis(RuntimeSupervisor.manager_name(Runtime)) do
      nil ->
        Process.sleep(10)
        await_new_manager(first_manager, attempts - 1)

      ^first_manager ->
        Process.sleep(10)
        await_new_manager(first_manager, attempts - 1)

      manager ->
        manager
    end
  end

  defp await_new_runtime_manager(first_manager, runtime, attempts \\ 100)

  defp await_new_runtime_manager(_first_manager, _runtime, 0),
    do: flunk("manager did not restart")

  defp await_new_runtime_manager(first_manager, runtime, attempts) do
    case Process.whereis(RuntimeSupervisor.manager_name(runtime)) do
      nil ->
        Process.sleep(10)
        await_new_runtime_manager(first_manager, runtime, attempts - 1)

      ^first_manager ->
        Process.sleep(10)
        await_new_runtime_manager(first_manager, runtime, attempts - 1)

      manager ->
        manager
    end
  end

  defp await_room_pid(first, attempts \\ 100)

  defp await_room_pid(_first, 0), do: flunk("room was not restored")

  defp await_room_pid(first, attempts) do
    case Runtime.room_runtime_status("team") do
      {:ok, %{state: :running, pid: pid}} when pid != first ->
        pid

      _other ->
        Process.sleep(10)
        await_room_pid(first, attempts - 1)
    end
  end
end
