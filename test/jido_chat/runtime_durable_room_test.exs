defmodule Jido.Chat.RuntimeDurableRoomTest do
  use ExUnit.Case, async: false

  alias Jido.Chat.{Content, Post}
  alias Jido.Chat.Runtime.Room
  alias Jido.Chat.Runtime.Room.Declaration
  alias Jido.Chat.Runtime.Signal.Room.Join
  alias Jido.Chat.Runtime.Storage.Memory

  defmodule Runtime do
    use Jido.Chat.Runtime,
      jido: Jido.Chat.RuntimeDurableRoomTest.Jido,
      storage: {Memory, Jido.Chat.RuntimeDurableRoomTest.Storage},
      room_definitions: %{"team" => Jido.Chat.RuntimeDurableRoomTest.Team}
  end

  defmodule Team do
    use Jido.Chat.Runtime.Room, name: "durable_team"

    room do
      admin("operator")
      runtime(Runtime)
      history_limit(2)
      member_limit(10)
    end
  end

  setup do
    {:ok, _} = Application.ensure_all_started(:jido)
    start_supervised!({Memory, name: __MODULE__.Storage})

    start_supervised!({Jido, name: __MODULE__.Jido, namespace: "durable-room-test"})

    start_runtime()
    :ok
  end

  test "provisions and restores desired state, membership, and history" do
    assert {:ok,
            %{
              room: %{id: "team"},
              declaration: %{definition_key: "team", desired: :running},
              activation: {:ok, %{state: :running, source: :durable}}
            }} = Runtime.provision_room("team", %{id: "team", kind: :group, name: "Team"})

    join("operator", "operator")
    join("alice", "operator")

    first = post("one", "alice")
    _second = post("two", "alice")
    third = post("three", "alice")

    assert {:ok, history} = Runtime.list_room_history("team")
    assert Enum.map(history, & &1.sequence) == [1, 2, 3]
    assert {:ok, memberships} = Runtime.list_room_memberships("team", status: :active)
    assert Enum.map(memberships, &Room.Membership.member/1) == ["alice", "operator"]

    assert :ok = stop_supervised(Runtime)
    assert :ok = stop_supervised(__MODULE__.Jido)

    start_supervised!({Jido, name: __MODULE__.Jido, namespace: "durable-room-test"})

    start_runtime()

    assert {:ok, %{state: :running, pid: pid}} = Runtime.room_runtime_status("team")
    state = snapshot(pid)
    assert MapSet.new(state.room.members) == MapSet.new(["alice", "operator"])
    assert Enum.map(state.room.messages, & &1.id) == [history |> Enum.at(1) |> then(& &1.message_id), third.id]
    assert state.room.sequence == 3

    repeated = post("one", "alice", id: first.id)
    assert repeated.id == first.id
    assert {:ok, history} = Runtime.list_room_history("team")
    assert length(history) == 3

    assert {:ok, %{desired: :stopped, state: :stopped}} = Runtime.stop_managed_room("team")
    assert :ok = stop_supervised(Runtime)
    start_runtime()
    assert {:ok, %{desired: :stopped, state: :stopped}} = Runtime.room_runtime_status("team")

    assert {:ok, %{state: :running}} = Runtime.start_managed_room("team")
    assert :ok = Runtime.deprovision_room("team")
    assert {:error, :not_managed} = Runtime.room_runtime_status("team")
    assert {:ok, %{id: "team"}} = Runtime.get_room("team")
    assert {:ok, [_ | _]} = Runtime.list_room_memberships("team")
    assert {:ok, [_, _, _]} = Runtime.list_room_history("team")
  end

  test "rejects unknown definitions before it writes Room data" do
    assert {:error, :unknown_room_definition} =
             Runtime.provision_room("missing", %{id: "unknown", kind: :group})

    assert {:error, :not_found} = Runtime.get_room("unknown")
  end

  test "reports an unknown stored definition key without resolving a module" do
    declaration = Declaration.new!(%{room_id: "unknown", definition_key: "not-registered"})
    assert {:ok, ^declaration} = Memory.insert_room_declaration(__MODULE__.Storage, declaration)
    assert {:error, {:reconcile_failed, 1, _status}} = Runtime.reconcile_runtime()

    assert {:ok, %{state: :error, error: :unknown_room_definition, definition_key: "not-registered"}} =
             Runtime.room_runtime_status("unknown")
  end

  test "rolls back the declaration when provisioning conflicts with a Room record" do
    assert {:ok, _room} = Runtime.create_room(%{id: "team", kind: :group})
    assert {:error, :room_conflict} = Runtime.provision_room("team", %{id: "team", kind: :group})
    assert {:ok, nil} = Memory.get_room_declaration(__MODULE__.Storage, "team")
  end

  test "reports a declaration storage failure in Runtime health" do
    assert {:ok, _result} = Runtime.provision_room("team", %{id: "team", kind: :group})
    assert {:ok, %{pid: room_pid}} = Runtime.room_runtime_status("team")
    assert :ok = stop_supervised(Memory)

    assert {:error, {:reconcile_failed, 1, status}} = Runtime.reconcile_runtime()
    assert status.healthy == false
    assert status.declaration_error == :room_storage_unavailable
    assert [%{state: :running, pid: ^room_pid, error: nil}] = status.rooms
    assert :ok = stop_supervised(Runtime)
    refute Process.alive?(room_pid)
  end

  test "an active member outside the working cache remains authorized" do
    memberships =
      for index <- 1..11 do
        membership =
          Room.Membership.new!(%{
            room_id: "team",
            member: "member-#{index}",
            issuer: "operator"
          })

        assert {:ok, ^membership} = Memory.insert_membership(__MODULE__.Storage, membership)
        membership
      end

    assert {:ok, _result} = Runtime.provision_room("team", %{id: "team", kind: :group})
    assert {:ok, %{pid: pid}} = Runtime.room_runtime_status("team")
    cached = snapshot(pid).room.members
    assert length(cached) == 10

    [outside_cache] = Enum.map(memberships, &Room.Membership.member/1) -- cached

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(Runtime.jido(), room(), post_signal("allowed"), context: %{actor: outside_cache})

    repeated_join = Join.new!(%{"member" => outside_cache})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(Runtime.jido(), room(), repeated_join, context: %{actor: "operator"})
  end

  test "deprovision stops a matching orphan when the Runtime manager is down" do
    assert {:ok, _result} = Runtime.provision_room("team", %{id: "team", kind: :group})
    assert {:ok, %{pid: managed}} = Runtime.room_runtime_status("team")
    assert :ok = stop_supervised(Runtime)
    refute Process.alive?(managed)

    ref = room()
    assert {:ok, orphan} = Room.start_agent(Runtime.jido(), ref, Team)
    assert :ok = Jido.AgentServer.await_ready(orphan)
    assert Process.alive?(orphan)

    assert :ok = Runtime.deprovision_room("team")
    refute Process.alive?(orphan)
    assert {:ok, nil} = Memory.get_room_declaration(__MODULE__.Storage, "team")
    assert {:ok, %{id: "team"}} = Runtime.get_room("team")
  end

  test "leaving updates durable authorization before a later post" do
    assert {:ok, _result} = Runtime.provision_room("team", %{id: "team", kind: :group})
    join("operator", "operator")
    join("alice", "operator")

    leave = Jido.Chat.Runtime.Signal.Room.Leave.new!(%{"member" => "alice"})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(Runtime.jido(), room(), leave, context: %{actor: "alice"})

    assert {:ok, %{status: :revoked, revision: 2}} =
             Runtime.get_room_membership("team", "alice")

    request = post_signal("denied")

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed}} =
             Jido.call(Runtime.jido(), room(), request, context: %{actor: "alice"})
  end

  defp start_runtime do
    start_supervised!({Runtime, reconcile_interval: :infinity})
  end

  defp room do
    {:ok, room} = Jido.agent_address(Runtime.jido(), "team")
    room
  end

  defp join(member, actor) do
    request = Join.new!(%{"member" => member})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(Runtime.jido(), room(), request, context: %{actor: actor})
  end

  defp post(text, actor, opts \\ []) do
    request = post_signal(text, opts)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed, reply: reply}} =
             Jido.call(Runtime.jido(), room(), request, context: %{actor: actor})

    reply.data["message"]
  end

  defp post_signal(text, opts \\ []) do
    post = Post.new(%{content: [Content.text(text)]})
    Jido.Chat.Runtime.Signal.Room.Post.new!(%{"post" => Post.to_map(post), "mentions" => []}, opts)
  end

  defp snapshot(pid), do: Jido.AgentServer.snapshot(pid).agent.state
end
