defmodule Jido.Chat.Telegram.MembershipRuntimeTest do
  use ExUnit.Case, async: false
  alias Jido.Chat.{Delivery, Handlers, WebhookRequest}
  alias Jido.Chat.Telegram.Adapter
  alias Jido.Messaging.{AgentRunner, AuthorizationScope, RoomServer, RoomSupervisor, Runtime}

  defmodule Transport do
    @behaviour Jido.Chat.Telegram.Transport
    @impl true
    def call(_token, _method, _payload, _opts) do
      send(self(), :unexpected_provider_call)
      {:error, :unexpected_provider_call}
    end
  end

  defmodule Instance do
    use Jido.Messaging, persistence: Jido.Messaging.Persistence.ETS, runtime_profile: :core
  end

  setup do
    start_supervised!(Instance)

    {:ok, binding} =
      Jido.Chat.bind(Adapter,
        id: "telegram-runtime-membership",
        token: "fixture-token",
        transport: Transport,
        bot_id: 99
      )

    :ok = Runtime.register_binding(Instance.__jido_messaging__(:runtime), binding)
    {:ok, room} = Instance.get_or_create_room_by_external_binding(:telegram, binding.id, "-123", %{type: :group})
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

  defp member(status, extra \\ %{}), do: Map.merge(%{"status" => status, "user" => %{"id" => 42}}, extra)

  defp payload(id, previous, current, room \\ -123) do
    %{
      "update_id" => id,
      "chat_member" => %{
        "chat" => %{"id" => room},
        "from" => nil,
        "old_chat_member" => previous,
        "new_chat_member" => current
      }
    }
  end

  @cases [
    {"join", "left", "member", %{}, "joined"},
    {"leave", "member", "left", %{}, "left"},
    {"remove", "member", "kicked", %{}, "removed"},
    {"role", "member", "administrator", %{}, "role_changed"},
    {"restricted member", "member", "restricted",
     %{"is_member" => true, "can_react_to_messages" => false, "can_edit_tag" => false, "until_date" => 100},
     "restriction_changed"},
    {"restricted non-member", "member", "restricted", %{"is_member" => false}, "left"}
  ]
  for {label, previous, current, extra, transition} <- @cases do
    test "real Telegram #{label} changes only native observations", context do
      request =
        WebhookRequest.new(%{
          adapter_name: :telegram,
          payload: payload(10, member(unquote(previous)), member(unquote(current), unquote(Macro.escape(extra))))
        })

      assert :ok = Adapter.verify_webhook(request, context.binding.options)
      assert {:ok, %Delivery{signals: [parent]} = unit} = Jido.Chat.normalize_event(context.binding, request)
      assert parent.data["transition"] == unquote(transition)
      assert parent.data["actor_id"] == nil
      original = Jido.Signal.to_map(parent)
      before = snapshot()
      room_before = :sys.get_state(context.server)
      {:ok, _} = Instance.subscribe_signals("jido.messaging.**")
      assert {:ok, [observed]} = Instance.accept_delivery(unit)
      assert_receive {:signal, ^observed}
      assert observed.type == "jido.messaging.membership.observed"
      assert observed.data["room_id"] == context.room.id
      assert observed.data["current"] == parent.data["current"]
      assert Jido.Signal.Context.get(observed, "causationid") == parent.id
      assert Jido.Signal.Trace.get(observed).trace_id == Jido.Signal.Trace.get(parent).trace_id
      assert Jido.Signal.to_map(parent) == original
      {:ok, catalog} = Runtime.catalog(Instance.__jido_messaging__(:runtime))
      assert {:ok, json} = Jido.Signal.Serialization.serialize(observed)
      assert {:ok, ^observed} = Jido.Signal.Catalog.decode(catalog, json)
      assert {:ok, batch} = Jido.Chat.normalize_event(context.binding, [request.payload])
      assert {:ok, []} = Instance.accept_delivery(batch)
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
             Jido.Chat.normalize_event(context.binding, payload(11, nil, member("member"), -456))

    assert {:ok, [observed]} = Instance.accept_delivery(unit)
    assert observed.subject == nil
    assert observed.data["room_id"] == nil
    assert observed.data["previous"] == nil
    assert observed.data["transition"] == "unknown"
    assert observed.data["evidence"] == "partial_transition"
    assert observed.data["external_room_id"] == "-456"
    assert Jido.Signal.Context.get(observed, "causationid") == parent.id
    _ = :sys.get_state(context.runner)
    assert snapshot() == before
    refute_received :agent_handled
    refute_received :unexpected_provider_call
  end

  test "bot-self membership remains observation only with an active agent", context do
    update = payload(13, member("left"), member("administrator"))
    update = Map.put(update, "my_chat_member", update["chat_member"]) |> Map.delete("chat_member")
    before = snapshot()
    room_before = :sys.get_state(context.server)
    assert {:ok, %{signals: [parent]} = unit} = Jido.Chat.normalize_event(context.binding, update)
    assert parent.data["bot_self"]
    assert {:ok, [observed]} = Instance.accept_delivery(unit)
    assert observed.data["bot_self"]
    assert observed.data["current"] == parent.data["current"]
    assert {:ok, []} = Instance.accept_delivery(unit)
    _ = :sys.get_state(context.runner)
    assert snapshot() == before
    assert :sys.get_state(context.server) == room_before
    refute_received :agent_handled
    refute_received :unexpected_provider_call
    {:ok, catalog} = Runtime.catalog(Instance.__jido_messaging__(:runtime))
    assert {:ok, json} = Jido.Signal.Serialization.serialize(observed)
    assert {:ok, ^observed} = Jido.Signal.Catalog.decode(catalog, json)
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

    assert {:ok, unit} = Jido.Chat.normalize_event(context.binding, payload(12, member("left"), member("member")))
    assert {:ok, handlers, _} = Handlers.accept(handlers, context.binding, unit)
    assert_receive :membership_handler
    assert {:ok, _, _} = Handlers.accept(handlers, context.binding, unit)
    refute_received :membership_handler
    refute_received :message_handler
    refute_received :mention_handler
  end
end
