defmodule Jido.Chat.RuntimeManagerTest do
  use ExUnit.Case, async: false

  alias Jido.Chat.Runtime.Room
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

  setup do
    {:ok, _} = Application.ensure_all_started(:jido)

    start_supervised!(
      {Jido,
       name: Jido.Chat.RuntimeManagerTest.Jido,
       namespace: "chat-runtime-manager-test-#{System.unique_integer([:positive])}"}
    )

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

    assert [{Jido.Chat.Runtime.Manager, manager, :worker, [Jido.Chat.Runtime.Manager]}] =
             Supervisor.which_children(runtime_supervisor)

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
    assert {:ok, ref, account} = Runtime.start_connection("direct", Account)
    assert {:ok, ^account} = Jido.resolve_agent(Runtime.jido(), ref)
    assert :ok = Runtime.stop_connection("direct")
  end

  defp start_runtime(opts) do
    start_supervised!({Runtime, Keyword.put_new(opts, :reconcile_interval, :infinity)})
  end

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
