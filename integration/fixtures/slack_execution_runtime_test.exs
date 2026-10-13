defmodule Jido.Chat.Slack.ExecutionRuntimeTest do
  use ExUnit.Case, async: false
  alias Jido.Chat.Slack.Adapter
  alias Jido.Messaging.{AuthorizationScope, Runtime}

  defmodule Instance do
    use Jido.Messaging, persistence: Jido.Messaging.Persistence.ETS, runtime_profile: :core
  end

  defmodule Transport do
    def send_message(room, text, opts) do
      record(opts, {:send_message, room, text})
      {:ok, %{"channel" => room, "ts" => "1.01", "token" => opts[:token]}}
    end

    def fetch_messages(room, opts) do
      record(opts, {:fetch_messages, room, opts[:cursor], opts[:limit]})

      {:ok,
       %{
         "messages" => [
           %{"channel" => room, "ts" => "1.01", "text" => "first"},
           %{"channel" => room, "ts" => "1.02", "text" => "second"}
         ],
         "has_more" => true,
         "response_metadata" => %{"next_cursor" => "next-page"}
       }}
    end

    def open_modal(trigger, view, opts) do
      record(opts, {:open_modal, trigger, view["title"]["text"]})
      {:ok, %{"view" => %{"id" => "V1"}}}
    end

    defp record(opts, call), do: Agent.update(opts[:req][:capture], &(&1 ++ [call]))
  end

  setup do
    start_supervised!(Instance)
    capture = start_supervised!({Agent, fn -> [] end})

    {:ok, binding} =
      Jido.Chat.bind(Adapter,
        id: "slack-execution",
        token: "fixture-token",
        transport: Transport,
        req: [capture: capture]
      )

    :ok = Runtime.register_binding(Instance.__jido_messaging__(:runtime), binding)
    {:ok, room} = Instance.get_or_create_room_by_external_binding(:slack, binding.id, "C1", %{type: :channel})
    {:ok, participant} = Instance.create_participant(%{type: :human})

    {:ok, _} =
      Instance.create_membership(%{principal_id: participant.id, room_id: room.id, issuer_principal_id: "host"})

    scope = AuthorizationScope.new(%{kind: :room, room_id: room.id, bridge_id: binding.id})

    {:ok, grant} =
      Instance.create_principal_grant(%{
        principal_id: participant.id,
        issuer_principal_id: "host",
        actions: [:post_message, :fetch_channel_messages],
        scope: scope,
        constraints: %{max_results: 2}
      })

    %{binding: binding, capture: capture, room: room, participant: participant, scope: scope, grant: grant}
  end

  defp actor(context), do: [principal_id: context.participant.id, authorization_scope: context.scope]
  defp calls(context), do: Agent.get(context.capture, & &1)

  defp request(context, definition, data) do
    definition.new!(
      Map.merge(
        %{"request_id" => Atom.to_string(definition), "room_id" => context.room.id, "bridge_id" => context.binding.id},
        data
      )
    )
  end

  defp portable_result(context, parent, result) do
    assert result.type == "jido.messaging.operation.completed"
    assert result.subject == Jido.Messaging.Signal.Identity.room_subject(context.room.id)
    assert Jido.Signal.Context.get(result, "causationid") == parent.id
    assert Jido.Signal.Trace.get(result).trace_id == Jido.Signal.Trace.get(parent).trace_id
    {:ok, catalog} = Runtime.catalog(Instance.__jido_messaging__(:runtime))
    assert {:ok, json} = Jido.Signal.Serialization.serialize(result)
    assert {:ok, ^result} = Jido.Signal.Catalog.decode(catalog, json)
    refute json =~ "fixture-token"
    refute json =~ "capture"
  end

  test "native Messaging send uses one real Slack callback and checks revoked authority before a cached result",
       context do
    parent = request(context, Jido.Messaging.Signal.SendMessage, %{"text" => "hello"})
    before = Jido.Signal.to_map(parent)
    assert {:ok, result} = Instance.execute(parent, actor(context))
    portable_result(context, parent, result)
    assert result.data["result"]["id"] == "1.01"
    assert calls(context) == [{:send_message, "C1", "hello"}]
    assert {:ok, ^result} = Instance.execute(parent, actor(context))
    assert calls(context) == [{:send_message, "C1", "hello"}]
    assert Jido.Signal.to_map(parent) == before
    assert {:ok, _} = Instance.revoke_principal_grant(context.grant.id, context.grant.revision)
    assert {:ok, denied} = Instance.execute(parent, actor(context))
    assert denied.data["code"] == "authorization_denied"
    assert calls(context) == [{:send_message, "C1", "hello"}]
  end

  test "native Messaging history keeps every Slack item and cursor and applies the grant limit", context do
    parent =
      request(context, Jido.Messaging.Signal.FetchChannelMessages, %{
        "cursor" => "prior-page",
        "limit" => 20,
        "direction" => "backward"
      })

    assert {:ok, result} = Instance.execute(parent, actor(context))
    portable_result(context, parent, result)
    page = result.data["result"]
    assert Enum.map(page["messages"], & &1["id"]) == ["1.01", "1.02"]
    assert page["next_cursor"] == "next-page"
    assert page["complete"] == false
    assert calls(context) == [{:fetch_messages, "C1", "prior-page", 2}]
    assert {:ok, ^result} = Instance.execute(parent, actor(context))
    assert length(calls(context)) == 1
  end

  test "an incorrect canonical scope causes zero Slack calls", context do
    parent = request(context, Jido.Messaging.Signal.SendMessage, %{"text" => "hello"})

    assert {:ok, denied} =
             Instance.execute(parent,
               principal_id: context.participant.id,
               authorization_scope: %{context.scope | room_id: "other"}
             )

    assert denied.data["code"] == "authorization_denied"
    assert calls(context) == []
  end

  test "a private interaction opens a modal through Messaging and retains its conversation", context do
    assert {:ok, %{signals: [action]} = delivery} =
             Jido.Chat.normalize_event(context.binding, %{
               "type" => "block_actions",
               "container" => %{"channel_id" => "C1"},
               "trigger_id" => "private-trigger",
               "actions" => [%{"action_id" => "open"}]
             })

    assert {:ok, []} = Instance.accept_delivery(delivery)
    assert {:ok, modal} = Adapter.prepare_modal(context.binding, action.data["interaction_id"], %{title: "Modal"})
    parent = request(context, Jido.Messaging.Signal.OpenModal, %{"modal" => modal})
    before = Jido.Signal.to_map(parent)
    assert {:ok, result} = Instance.execute(parent, actor(context))
    portable_result(context, parent, result)
    assert result.data["result"] == %{"opened" => true, "id" => "V1"}
    assert calls(context) == [{:open_modal, "private-trigger", "Modal"}]
    assert {:ok, ^result} = Instance.execute(parent, actor(context))
    assert calls(context) == [{:open_modal, "private-trigger", "Modal"}]
    assert Jido.Signal.to_map(parent) == before

    assert {:ok, %{signals: [submitted]} = submission} =
             Jido.Chat.normalize_event(context.binding, %{"type" => "view_submission", "view" => %{"id" => "V1"}})

    assert submitted.subject == Jido.Chat.Signal.Identity.conversation_subject(context.binding.id, "C1")
    assert {:ok, []} = Instance.accept_delivery(submission)
    assert {:ok, json} = Jido.Signal.Serialization.serialize(submitted)
    refute json =~ "private-trigger"
    assert {:ok, []} = Instance.list_messages(context.room.id)
  end

  test "native Slack interaction observation selects the exact binding and conversation", context do
    {:ok, other} =
      Jido.Chat.bind(Adapter,
        id: "slack-other",
        token: "other-fixture-token",
        transport: Transport,
        req: [capture: context.capture]
      )

    :ok = Runtime.register_binding(Instance.__jido_messaging__(:runtime), other)

    {:ok, _} =
      Instance.subscribe_signals("jido.chat.action.received",
        selector: [
          source: context.binding.source,
          subject: Jido.Chat.Signal.Identity.conversation_subject(context.binding.id, "C1")
        ]
      )

    for {binding, room, selected} <- [
          {context.binding, "C1", true},
          {context.binding, "C2", false},
          {other, "C1", false}
        ] do
      payload = %{
        "type" => "block_actions",
        "channel" => %{"id" => room},
        "user" => %{"id" => "U1"},
        "trigger_id" => "private-trigger",
        "actions" => [%{"action_id" => "confirm", "value" => "yes"}]
      }

      assert {:ok, %{signals: [parent]} = unit} = Jido.Chat.normalize_event(binding, payload)
      before = Jido.Signal.to_map(parent)
      assert {:ok, []} = Instance.accept_delivery(unit)
      if selected, do: assert_receive({:signal, ^parent}), else: refute_receive({:signal, _})
      assert {:ok, []} = Instance.accept_delivery(unit)
      refute_receive {:signal, _}
      assert Jido.Signal.to_map(parent) == before
      assert {:ok, json} = Jido.Signal.Serialization.serialize(parent)
      refute json =~ "private-trigger"
      refute json =~ "fixture-token"
    end

    assert calls(context) == []
    assert {:ok, []} = Instance.list_messages(context.room.id)
  end
end
