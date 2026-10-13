defmodule Jido.Chat.Telegram.MembershipRuntimeTest do
  use ExUnit.Case, async: false

  alias Jido.Chat.{Delivery, Telegram.Membership}
  alias Jido.Messaging.Runtime

  defmodule FixtureAdapter do
    def channel_type, do: :telegram
    def signal_protocol, do: 1
    def configure_binding(opts), do: {:ok, opts}
    def normalize_event(_binding, _input), do: Jido.Chat.Signal.Policy.error(:invalid_delivery)
  end

  defmodule Instance do
    use Jido.Messaging, persistence: Jido.Messaging.Persistence.ETS, runtime_profile: :core
  end

  setup do
    start_supervised!(Instance)
    {:ok, binding} = Jido.Chat.bind(FixtureAdapter, id: "telegram-runtime-membership")
    :ok = Runtime.register_binding(Instance.__jido_messaging__(:runtime), binding)
    %{binding: binding}
  end

  defp snapshot do
    {_, state} = Runtime.get_persistence(Instance.__jido_messaging__(:runtime))
    Map.new(Map.from_struct(state), fn {name, table} -> {name, Enum.sort(:ets.tab2list(table))} end)
  end

  for known <- [true, false] do
    test "a #{if known, do: "resolved", else: "partial"} Telegram restriction remains an observation", context do
      room_id =
        if unquote(known) do
          {:ok, room} =
            Instance.get_or_create_room_by_external_binding(:telegram, context.binding.id, "-123", %{type: :group})

          room.id
        end

      before = snapshot()
      {:ok, _} = Instance.subscribe_signals("jido.messaging.**")

      member = %{
        "status" => "restricted",
        "user" => %{"id" => 42},
        "is_member" => true,
        "can_react_to_messages" => false,
        "can_edit_tag" => false,
        "until_date" => 100
      }

      payload = %{"chat" => %{"id" => -123}, "old_chat_member" => nil, "new_chat_member" => member}
      assert {:ok, parent} = Membership.normalize(context.binding, "update:1", "chat_member", payload)
      original = Jido.Signal.to_map(parent)
      {:ok, unit} = Delivery.new(context.binding, "update:1", [parent])

      assert {:ok, [observed]} = Instance.accept_delivery(unit)
      assert_receive {:signal, ^observed}
      assert observed.type == "jido.messaging.membership.observed"
      assert observed.data["room_id"] == room_id
      assert observed.data["current"] == parent.data["current"]
      assert observed.data["previous"] == nil
      assert Jido.Signal.Context.get(observed, "causationid") == parent.id
      assert Jido.Signal.Trace.get(observed).trace_id == Jido.Signal.Trace.get(parent).trace_id
      assert Jido.Signal.to_map(parent) == original
      assert snapshot() == before
      {:ok, catalog} = Runtime.catalog(Instance.__jido_messaging__(:runtime))
      assert {:ok, json} = Jido.Signal.Serialization.serialize(observed)
      assert {:ok, ^observed} = Jido.Signal.Catalog.decode(catalog, json)

      assert {:ok, repeated_parent} = Membership.normalize(context.binding, "update:1", "chat_member", payload)
      {:ok, repeated} = Delivery.new(context.binding, "update:1", [repeated_parent])
      assert {:ok, []} = Instance.accept_delivery(repeated)
      assert snapshot() == before
      refute_received {:signal, _}
    end
  end
end
