defmodule Jido.Chat.RuntimeDurableRoomTest do
  use ExUnit.Case, async: false

  alias Jido.Chat.{Content, Post}
  alias Jido.Chat.Runtime.Room
  alias Jido.Chat.Runtime.Room.Declaration
  alias Jido.Chat.Runtime.Signal.Room.{AddReaction, Join, RemoveReaction}
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

  test "stores reaction state before it publishes canonical facts" do
    assert {:ok, _result} = Runtime.provision_room("team", %{id: "team", kind: :group})
    join("operator", "operator")
    join("alice", "operator")
    message = post("react here", "alice")

    {:ok, bus} = Jido.Signal.Bus.whereis(Room.bus_name(room()), jido: Runtime.jido())
    assert {:ok, _subscription} = Jido.Signal.Bus.subscribe(bus, "jido.chat.reaction.*")

    add = reaction_request(AddReaction, message.id, "eyes")

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed, reply: added}} =
             Jido.call(Runtime.jido(), room(), add, context: %{actor: "alice"})

    assert added.type == "jido.chat.room.reaction.changed"
    assert added.data["status"] == "active"
    assert added.data["revision"] == 1
    assert added.data["changed"] == true
    assert %Jido.Signal{type: "jido.chat.reaction.added"} = added.data["fact"]
    assert Jido.Signal.get_context(added, "jidocausationid") == add.id

    assert {:ok, stored} = Runtime.get_room_reaction("team", message.id, "eyes", "alice")
    assert stored.status == :active
    assert stored.id == added.data["record_id"]
    assert_receive {:signal, %Jido.Signal{type: "jido.chat.reaction.added", id: added_fact_id}}
    assert added_fact_id == added.data["fact"].id

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed, reply: repeated}} =
             Jido.call(Runtime.jido(), room(), add, context: %{actor: "alice"})

    assert repeated.data["changed"] == false
    assert repeated.data["revision"] == 1
    assert repeated.data["fact"] == nil
    refute_receive {:signal, %Jido.Signal{type: "jido.chat.reaction.added"}}, 50

    remove = reaction_request(RemoveReaction, message.id, "eyes")

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed, reply: removed}} =
             Jido.call(Runtime.jido(), room(), remove, context: %{actor: "alice"})

    assert removed.data["status"] == "removed"
    assert removed.data["revision"] == 2
    assert removed.data["changed"] == true
    assert %Jido.Signal{type: "jido.chat.reaction.removed"} = removed.data["fact"]
    assert_receive {:signal, %Jido.Signal{type: "jido.chat.reaction.removed"}}

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed, reply: repeated_remove}} =
             Jido.call(Runtime.jido(), room(), remove, context: %{actor: "alice"})

    assert repeated_remove.data["changed"] == false
    assert repeated_remove.data["revision"] == 2
    assert repeated_remove.data["fact"] == nil
    refute_receive {:signal, %Jido.Signal{type: "jido.chat.reaction.removed"}}, 50
    assert {:ok, []} = Runtime.list_room_reactions("team", message_id: message.id)
    assert {:ok, [stored_removed]} = Runtime.list_room_reactions("team", message_id: message.id, status: :removed)
    assert stored_removed.revision == 2

    assert :ok = stop_supervised(Runtime)
    assert :ok = stop_supervised(__MODULE__.Jido)
    start_supervised!({Jido, name: __MODULE__.Jido, namespace: "durable-room-test"})
    start_runtime()

    assert {:ok, %{state: :running}} = Runtime.room_runtime_status("team")
    assert {:ok, restored} = Runtime.get_room_reaction("team", message.id, "eyes", "alice")
    assert restored.status == :removed
    assert restored.revision == 2

    add_after_restart = reaction_request(AddReaction, message.id, "eyes")

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed, reply: readded}} =
             Jido.call(Runtime.jido(), room(), add_after_restart, context: %{actor: "alice"})

    assert readded.data["status"] == "active"
    assert readded.data["revision"] == 3
    assert readded.data["changed"] == true
  end

  test "requires an active member and a retained message for reactions" do
    assert {:ok, _result} = Runtime.provision_room("team", %{id: "team", kind: :group})
    join("operator", "operator")
    join("alice", "operator")
    message = post("react here", "alice")

    missing = reaction_request(AddReaction, "missing", "eyes")

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed}} =
             Jido.call(Runtime.jido(), room(), missing, context: %{actor: "alice"})

    other = history_record("other", "other-message")
    assert {:ok, ^other} = Memory.insert_history(__MODULE__.Storage, other)
    wrong_room = reaction_request(AddReaction, other.message_id, "eyes")

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed}} =
             Jido.call(Runtime.jido(), room(), wrong_room, context: %{actor: "alice"})

    request = reaction_request(AddReaction, message.id, "eyes")

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed}} =
             Jido.call(Runtime.jido(), room(), request, context: %{actor: "outsider"})

    assert {:ok, []} = Runtime.list_room_reactions("team", status: :active)
    assert {:error, :invalid_options} = Runtime.list_room_reactions("team", :invalid)
    assert {:error, :invalid_options} = Runtime.list_room_reactions("team", [1])
  end

  test "does not publish a reaction fact when durable storage is unavailable" do
    assert {:ok, _result} = Runtime.provision_room("team", %{id: "team", kind: :group})
    join("operator", "operator")
    join("alice", "operator")
    message = post("react here", "alice")
    {:ok, bus} = Jido.Signal.Bus.whereis(Room.bus_name(room()), jido: Runtime.jido())
    assert {:ok, _subscription} = Jido.Signal.Bus.subscribe(bus, "jido.chat.reaction.*")
    assert :ok = stop_supervised(Memory)

    request = reaction_request(AddReaction, message.id, "eyes")

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed}} =
             Jido.call(Runtime.jido(), room(), request, context: %{actor: "alice"})

    refute_receive {:signal, %Jido.Signal{type: "jido.chat.reaction.added"}}, 50
  end

  test "uses retained history as the minimum thread projection" do
    assert {:ok, _result} = Runtime.provision_room("team", %{id: "team", kind: :group})
    join("operator", "operator")
    join("alice", "operator")
    root = post("root", "alice")
    reply = post_in_thread("reply", "alice", root.id)

    assert {:ok, [thread_reply]} = Runtime.list_room_history("team", thread_id: root.id)
    assert thread_reply.message_id == reply.id
    assert thread_reply.thread_id == root.id
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

  defp post_in_thread(text, actor, thread_id) do
    post = Post.new(%{content: [Content.text(text)], thread_id: thread_id, reply_to_id: thread_id})
    request = Jido.Chat.Runtime.Signal.Room.Post.new!(%{"post" => Post.to_map(post), "mentions" => []})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed, reply: reply}} =
             Jido.call(Runtime.jido(), room(), request, context: %{actor: actor})

    reply.data["message"]
  end

  defp reaction_request(module, message_id, reaction) do
    module.new!(%{"message_id" => message_id, "reaction" => reaction})
  end

  defp history_record(room_id, message_id) do
    signal =
      Jido.Chat.Runtime.Signal.Room.Message.new!(
        %{
          "room" => Jido.Agent.Address.new!(%{namespace: "durable-room-test", id: room_id}),
          "sequence" => 1,
          "author" => "alice",
          "message" =>
            Jido.Chat.Message.to_map(
              Jido.Chat.Message.new(%{
                id: message_id,
                room_id: room_id,
                actor: Room.actor("alice"),
                content: [Content.text("other")]
              })
            ),
          "mentions" => []
        },
        id: message_id
      )

    Jido.Chat.Runtime.Room.HistoryRecord.new!(%{
      room_id: room_id,
      message_id: message_id,
      sequence: 1,
      signal: signal
    })
  end

  defp snapshot(pid), do: Jido.AgentServer.snapshot(pid).agent.state
end
