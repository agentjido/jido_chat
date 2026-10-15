defmodule Jido.Chat.Telegram.ExecutionRuntimeTest do
  use ExUnit.Case, async: false
  alias Jido.Chat.Telegram.Adapter
  alias Jido.Messaging.{AuthorizationScope, Runtime}

  defmodule Instance do
    use Jido.Messaging, persistence: Jido.Messaging.Persistence.ETS, runtime_profile: :core
  end

  defmodule Transport do
    @behaviour Jido.Chat.Telegram.Transport
    @impl true
    def call(_token, method, payload, opts) do
      Agent.update(opts[:adapter_opts][:capture], &(&1 ++ [{method, payload}]))
      {:ok, %{"message_id" => 1, "chat" => %{"id" => payload["chat_id"]}, "text" => payload["text"]}}
    end
  end

  setup do
    start_supervised!(Instance)
    capture = start_supervised!({Agent, fn -> [] end})

    {:ok, binding} =
      Jido.Chat.bind(Adapter,
        id: "telegram-execution",
        token: "fixture-token",
        transport: Transport,
        adapter_opts: [capture: capture]
      )

    :ok = Runtime.register_binding(Instance.__jido_messaging__(:runtime), binding)
    {:ok, room} = Instance.get_or_create_room_by_external_binding(:telegram, binding.id, "123", %{type: :group})
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

  test "Telegram send through Messaging preserves one provider call and rejects revoked authority", context do
    parent = request(context, Jido.Messaging.Signal.SendMessage, %{"text" => "hello"})
    before = Jido.Signal.to_map(parent)
    assert {:ok, result} = Instance.execute(parent, actor(context))
    portable_result(context, parent, result)
    assert result.data["result"]["id"] == "1"
    assert [{"sendMessage", payload}] = calls(context)
    assert payload["chat_id"] == "123"
    assert payload["text"] == "hello"
    assert {:ok, ^result} = Instance.execute(parent, actor(context))
    assert length(calls(context)) == 1
    assert Jido.Signal.to_map(parent) == before
    assert {:ok, _} = Instance.revoke_principal_grant(context.grant.id, context.grant.revision)
    assert {:ok, denied} = Instance.execute(parent, actor(context))
    assert denied.data["code"] == "authorization_denied"
    assert length(calls(context)) == 1
  end

  test "Telegram history is typed unsupported through Messaging with zero provider calls", context do
    parent = request(context, Jido.Messaging.Signal.FetchChannelMessages, %{"cursor" => "page", "limit" => 2})
    assert {:ok, failed} = Instance.execute(parent, actor(context))
    assert failed.type == "jido.messaging.operation.failed"
    assert failed.data["code"] == "unsupported"
    assert Jido.Signal.Context.get(failed, "causationid") == parent.id
    assert {:ok, ^failed} = Instance.execute(parent, actor(context))
    assert calls(context) == []
    {:ok, catalog} = Runtime.catalog(Instance.__jido_messaging__(:runtime))
    assert {:ok, json} = Jido.Signal.Serialization.serialize(failed)
    assert {:ok, ^failed} = Jido.Signal.Catalog.decode(catalog, json)
  end

  test "Telegram interactions select only the bound room and use application payload policy", context do
    {:ok, other} =
      Jido.Chat.bind(Adapter,
        id: "telegram-other",
        token: "fixture-token",
        transport: Transport,
        adapter_opts: [capture: context.capture]
      )

    :ok = Runtime.register_binding(Instance.__jido_messaging__(:runtime), other)
    {:ok, other_room} = Instance.get_or_create_room_by_external_binding(:telegram, other.id, "123", %{type: :group})
    assert other_room.id != context.room.id

    {:ok, _} =
      Instance.subscribe_signals("jido.chat.action.received",
        selector: [
          source: context.binding.source,
          subject: Jido.Chat.Signal.Identity.conversation_subject(context.binding.id, "123")
        ]
      )

    for {binding, room, value, selected} <- [
          {context.binding, 123, "allow", true},
          {context.binding, 123, "deny", true},
          {context.binding, 456, "allow", false},
          {other, 123, "allow", false}
        ] do
      payload = %{
        "update_id" => room + if(value == "deny", do: 1, else: 0),
        "callback_query" => %{
          "id" => value,
          "data" => value,
          "from" => %{"id" => 42},
          "message" => %{"message_id" => 1, "chat" => %{"id" => room}}
        }
      }

      assert {:ok, %{signals: [fact]} = unit} = Jido.Chat.normalize_event(binding, payload)
      before = Jido.Signal.to_map(fact)
      assert {:ok, []} = Instance.accept_delivery(unit)

      if selected do
        assert_receive {:signal, ^fact}
        # The Bus selects context. The application checks the payload.
        assert fact.data["value"] == "allow" == (value == "allow")
      else
        refute_receive {:signal, _}
      end

      assert {:ok, []} = Instance.accept_delivery(unit)
      refute_receive {:signal, _}
      assert Jido.Signal.to_map(fact) == before
    end

    assert calls(context) == []
    assert {:ok, []} = Instance.list_messages(context.room.id)
    assert {:ok, []} = Instance.list_messages(other_room.id)
  end
end
