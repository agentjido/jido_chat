defmodule Jido.Chat.Integration.G7BoundaryTest do
  use ExUnit.Case, async: false
  alias Jido.Messaging.{AgentRunner, AuthorizationScope, RoomServer, RoomSupervisor, Runtime}

  defmodule Instance do
    use Jido.Messaging, persistence: Jido.Messaging.Persistence.ETS, runtime_profile: :core
  end

  setup do
    start_supervised!(Instance)
    :ok
  end

  defp input("telegram") do
    {Jido.Chat.Telegram.Adapter, [token: "fixture-token"],
     %{
       "update_id" => 1,
       "message" => %{
         "message_id" => 1,
         "chat" => %{"id" => 1, "type" => "group"},
         "from" => %{"id" => 1},
         "text" => "body"
       }
     }}
  end

  defp input("slack") do
    {Jido.Chat.Slack.Adapter, [token: "fixture-token"],
     %{"type" => "message", "channel" => "C1", "user" => "U1", "ts" => "1.01", "text" => "body"}}
  end

  defp input("discord") do
    {Jido.Chat.Discord.Adapter, [],
     {:MESSAGE_CREATE,
      %{"id" => "m1", "channel_id" => "C1", "content" => "body", "author" => %{"id" => "u1"}}}}
  end

  defp input("github") do
    {Jido.Chat.GitHub.Adapter, [],
     %{
       "action" => "created",
       "repository" => %{"name" => "repo", "owner" => %{"login" => "owner"}},
       "issue" => %{"id" => 9, "number" => 42},
       "comment" => %{"id" => 1, "body" => "body", "user" => %{"id" => 1}}
     }}
  end

  defp input("signal") do
    {Jido.Chat.Signal.Adapter, [],
     %{
       "envelope" => %{
         "source" => "u1",
         "timestamp" => 1,
         "dataMessage" => %{"message" => "body", "timestamp" => 1}
       }
     }}
  end

  defp input("teams") do
    {Jido.Chat.Teams.Adapter, [],
     %{
       "type" => "message",
       "serviceUrl" => "https://fixture.test",
       "id" => "m1",
       "text" => "body",
       "conversation" => %{"id" => "C1", "conversationType" => "personal"},
       "from" => %{"id" => "u1"}
     }}
  end

  defp input("whatsapp") do
    {Jido.Chat.WhatsApp.Adapter, [],
     {:amarula, :messages_upsert,
      %{
        id: "g7",
        messages: [
          %{
            id: "m1",
            type: :text,
            channel_jid: "C1@g.us",
            from_jid: "u1@s.whatsapp.net",
            content: "body"
          }
        ]
      }}}
  end

  defp input("x") do
    {Jido.Chat.X.Adapter, [],
     %{
       "direct_message_events" => [
         %{
           "id" => "m1",
           "type" => "message_create",
           "message_create" => %{"sender_id" => "u1", "message_data" => %{"text" => "body"}}
         }
       ]
     }}
  end

  for provider <- ~w(telegram slack discord github signal teams whatsapp x) do
    test "#{provider} direct delivery keeps parent identity, trace and one stored observation" do
      {adapter, opts, payload} = input(unquote(provider))
      {:ok, binding} = Jido.Chat.bind(adapter, Keyword.put(opts, :id, "g7-" <> unquote(provider)))
      :ok = Runtime.register_binding(Instance.__jido_messaging__(:runtime), binding)
      assert {:ok, %{signals: [parent]} = unit} = Jido.Chat.normalize_event(binding, payload)
      assert parent.type == Jido.Chat.Signal.MessageReceived.type()
      before = Jido.Signal.to_map(parent)
      {:ok, _} = Instance.subscribe_signals("jido.messaging.message.received")
      assert {:ok, [child]} = Instance.accept_delivery(unit)
      assert_receive {:signal, ^child}
      assert Jido.Signal.to_map(parent) == before
      assert Jido.Signal.Context.get(child, "causationid") == parent.id
      assert Jido.Signal.Trace.get(child).trace_id == Jido.Signal.Trace.get(parent).trace_id
      {:ok, catalog} = Runtime.catalog(Instance.__jido_messaging__(:runtime))
      {:ok, json} = Jido.Signal.Serialization.serialize(child)
      assert {:ok, ^child} = Jido.Signal.Catalog.decode(catalog, json)
      assert {:ok, [_stored]} = Instance.list_messages(child.data["room_id"])
      assert {:ok, repeat} = Jido.Chat.normalize_event(binding, payload)
      assert repeat.id == unit.id
      assert hd(repeat.signals).data["item_id"] == parent.data["item_id"]
      assert {:ok, []} = Instance.accept_delivery(repeat)
      assert {:ok, [_stored]} = Instance.list_messages(child.data["room_id"])
      refute_received {:signal, _}
    end
  end

  defp snapshot do
    {_, state} = Runtime.get_persistence(Instance.__jido_messaging__(:runtime))

    Map.new(Map.from_struct(state), fn {name, table} ->
      {name, Enum.sort(:ets.tab2list(table))}
    end)
  end

  test "Teams membership leaves active agents, grants, runtime membership and presence unchanged" do
    {:ok, binding} = Jido.Chat.bind(Jido.Chat.Teams.Adapter, id: "g7-teams-membership")
    :ok = Runtime.register_binding(Instance.__jido_messaging__(:runtime), binding)

    {:ok, room} =
      Instance.get_or_create_room_by_external_binding(:teams, binding.id, "C1", %{type: :group})

    {:ok, participant} = Instance.create_participant(%{type: :human})

    {:ok, _} =
      Instance.create_membership(%{
        principal_id: participant.id,
        room_id: room.id,
        issuer_principal_id: "host"
      })

    scope = AuthorizationScope.new(%{kind: :room, room_id: room.id, bridge_id: binding.id})

    {:ok, _} =
      Instance.create_principal_grant(%{
        principal_id: participant.id,
        issuer_principal_id: "host",
        actions: [:post_message],
        scope: scope
      })

    {:ok, thread} = Instance.save_thread(%{room_id: room.id, external_thread_id: "thread"})
    owner = self()

    {:ok, _} =
      Instance.register_agent(room.id, %{
        agent_id: "alpha",
        handler: fn _, _ ->
          send(owner, :agent_handled)
          :noreply
        end
      })

    {:ok, _} = Instance.assign_thread(room.id, thread.id, "alpha")
    runner = AgentRunner.whereis(Instance, room.id, thread.id, "alpha")
    assert is_pid(runner)
    _ = :sys.get_state(runner)
    {:ok, server} = RoomSupervisor.get_or_start_room(Instance, room)
    :ok = RoomServer.add_participant(server, participant)
    :ok = RoomServer.update_presence(server, participant.id, :away)
    before = snapshot()
    room_before = :sys.get_state(server)

    activity = %{
      "type" => "conversationUpdate",
      "id" => "membership",
      "conversation" => %{"id" => "C1", "conversationType" => "channel"},
      "membersAdded" => [%{"id" => "u1"}, %{"id" => "u2"}],
      "membersRemoved" => [%{"id" => "u3"}]
    }

    assert {:ok, unit} = Jido.Chat.normalize_event(binding, activity)
    assert length(unit.signals) == 3
    parents = Enum.map(unit.signals, &Jido.Signal.to_map/1)
    assert {:ok, children} = Instance.accept_delivery(unit)
    assert length(children) == 3

    for {parent, child} <- Enum.zip(unit.signals, children) do
      assert child.type == Jido.Messaging.Signal.MembershipObserved.type()
      assert Jido.Signal.Context.get(child, "causationid") == parent.id
      assert Jido.Signal.Trace.get(child).trace_id == Jido.Signal.Trace.get(parent).trace_id
    end

    assert Enum.map(unit.signals, &Jido.Signal.to_map/1) == parents
    assert {:ok, []} = Instance.accept_delivery(unit)
    _ = :sys.get_state(runner)
    assert snapshot() == before
    assert :sys.get_state(server) == room_before
    refute_received :agent_handled
    {:ok, handlers} = Jido.Chat.Handlers.new()

    {:ok, handlers} =
      Jido.Chat.Handlers.on(handlers, Jido.Chat.Signal.MessageReceived, fn _ ->
        send(owner, :message_handled)
      end)

    assert {:ok, _, [:ok, :ok, :ok]} = Jido.Chat.Handlers.accept(handlers, binding, unit)

    refute_received :message_handled
  end
end
