defmodule Jido.Chat.Slack.MembershipRuntimeTest do
  use ExUnit.Case, async: false
  alias Jido.Chat.{Delivery, Handlers, WebhookRequest}
  alias Jido.Chat.Slack.Adapter
  alias Jido.Messaging.{AgentRunner, AuthorizationScope, RoomServer, RoomSupervisor, Runtime}

  defmodule Transport do
    @calls [
      send_message: 3,
      send_file: 3,
      edit_message: 4,
      delete_message: 3,
      fetch_metadata: 2,
      fetch_thread: 2,
      fetch_message: 3,
      get_user: 2,
      get_permalink: 3,
      mark_as_read: 3,
      download_file: 2,
      fetch_messages: 2,
      fetch_channel_messages: 2,
      list_threads: 2,
      add_reaction: 4,
      remove_reaction: 4,
      post_ephemeral: 4,
      open_dm: 2,
      open_modal: 3
    ]
    for {method, arity} <- @calls do
      args = Macro.generate_arguments(arity, __MODULE__)

      def unquote(method)(unquote_splicing(args)) do
        _ = [unquote_splicing(args)]
        send(self(), :unexpected_provider_call)
        {:error, :unexpected_provider_call}
      end
    end
  end

  defmodule Instance do
    use Jido.Messaging, persistence: Jido.Messaging.Persistence.ETS, runtime_profile: :core
  end

  setup do
    start_supervised!(Instance)

    {:ok, binding} =
      Jido.Chat.bind(Adapter,
        id: "slack-runtime-membership",
        token: "fixture-token",
        transport: Transport,
        bot_user_id: "UBOT"
      )

    :ok = Runtime.register_binding(Instance.__jido_messaging__(:runtime), binding)
    {:ok, room} = Instance.get_or_create_room_by_external_binding(:slack, binding.id, "C1", %{type: :group})
    {:ok, participant} = Instance.create_participant(%{type: :human, name: "Existing"})

    {:ok, _} =
      Instance.create_membership(%{principal_id: participant.id, room_id: room.id, issuer_principal_id: "host"})

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
        name: "Alpha",
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
    %{binding: binding, room: room, server: server, runner: runner}
  end

  defp snapshot do
    {_, state} = Runtime.get_persistence(Instance.__jido_messaging__(:runtime))
    Map.new(Map.from_struct(state), fn {name, table} -> {name, Enum.sort(:ets.tab2list(table))} end)
  end

  @fixtures __DIR__
            |> Path.join("slack_membership_partial.json")
            |> File.read!()
            |> Jason.decode!()
            |> Map.fetch!("cases")
  @cases @fixtures ++
           [
             %{
               "name" => "bot-self join",
               "provider" => %{"type" => "member_joined_channel", "user" => "UBOT", "channel" => "C1"},
               "normalized" => %{"bot_self" => true, "transition" => "joined", "previous" => nil}
             }
           ]
  for fixture <- @cases do
    test "real Slack #{fixture["name"]} changes only native observations", context do
      fixture = unquote(Macro.escape(fixture))
      payload = %{"event_id" => "event-10", "event" => fixture["provider"]}
      request = WebhookRequest.new(%{adapter_name: :slack, payload: payload})
      assert :ok = Adapter.verify_webhook(request, context.binding.options)
      assert {:ok, %Delivery{signals: [parent]} = unit} = Jido.Chat.normalize_event(context.binding, request)
      for {key, value} <- fixture["normalized"], do: assert(parent.data[key] == value)
      original = Jido.Signal.to_map(parent)
      before = snapshot()
      room_before = :sys.get_state(context.server)
      {:ok, _} = Instance.subscribe_signals("jido.messaging.**")
      assert {:ok, [observed]} = Instance.accept_delivery(unit)
      assert_receive {:signal, ^observed}
      assert observed.type == "jido.messaging.membership.observed"
      assert observed.data["room_id"] == context.room.id
      assert observed.data["current"] == parent.data["current"]
      assert observed.data["previous"] == nil
      assert Jido.Signal.Context.get(observed, "causationid") == parent.id
      assert Jido.Signal.Trace.get(observed).trace_id == Jido.Signal.Trace.get(parent).trace_id
      assert Jido.Signal.to_map(parent) == original
      {:ok, catalog} = Runtime.catalog(Instance.__jido_messaging__(:runtime))
      assert {:ok, json} = Jido.Signal.Serialization.serialize(observed)
      assert {:ok, ^observed} = Jido.Signal.Catalog.decode(catalog, json)

      assert {:ok, socket} =
               Jido.Chat.normalize_event(context.binding, %{
                 "type" => "events_api",
                 "envelope_id" => "socket-other",
                 "payload" => payload
               })

      assert hd(socket.signals).data["item_id"] == parent.data["item_id"]
      assert socket.id != unit.id
      assert {:ok, []} = Instance.accept_delivery(socket)
      _ = :sys.get_state(context.runner)
      assert snapshot() == before
      assert :sys.get_state(context.server) == room_before
      refute_received :agent_handled
      refute_received :unexpected_provider_call
      refute_received {:signal, _}
    end
  end

  test "unresolved room and absent prior state stay partial without record mutation", context do
    before = snapshot()

    assert {:ok, %{signals: [parent]} = unit} =
             Jido.Chat.normalize_event(context.binding, %{
               "event_id" => "event-11",
               "event" => %{"type" => "member_joined_channel", "channel" => "C2", "user" => "U1"}
             })

    assert {:ok, [observed]} = Instance.accept_delivery(unit)
    assert observed.subject == nil
    assert observed.data["room_id"] == nil
    assert observed.data["previous"] == nil
    assert observed.data["transition"] == "joined"
    assert observed.data["evidence"] == "explicit_join"
    assert observed.data["external_room_id"] == "C2"
    assert Jido.Signal.Context.get(observed, "causationid") == parent.id
    _ = :sys.get_state(context.runner)
    assert snapshot() == before
    refute_received :agent_handled
    refute_received :unexpected_provider_call
  end

  test "standalone membership handler never selects message or mention handlers", context do
    {:ok, handlers} = Handlers.new()

    {:ok, handlers} =
      Handlers.on(handlers, Jido.Chat.Signal.MessageReceived, fn _ -> send(self(), :message_handler) end,
        mode: :message
      )

    {:ok, handlers} =
      Handlers.on(handlers, Jido.Chat.Signal.MessageReceived, fn _ -> send(self(), :mention_handler) end,
        mode: :mention
      )

    {:ok, handlers} =
      Handlers.on(handlers, Jido.Chat.Signal.MembershipChanged, fn _ -> send(self(), :membership_handler) end)

    assert {:ok, unit} =
             Jido.Chat.normalize_event(context.binding, %{
               "event_id" => "event-12",
               "event" => %{"type" => "member_joined_channel", "channel" => "C1", "user" => "U1"}
             })

    assert {:ok, handlers, _} = Handlers.accept(handlers, context.binding, unit)
    assert_receive :membership_handler
    assert {:ok, _, _} = Handlers.accept(handlers, context.binding, unit)
    refute_received :membership_handler
    refute_received :message_handler
    refute_received :mention_handler
  end
end
