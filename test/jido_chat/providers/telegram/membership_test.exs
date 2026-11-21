defmodule Jido.Chat.Telegram.MembershipTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Signal.{Identity, MembershipChanged}
  alias Jido.Chat.Telegram.Membership

  defmodule FixtureAdapter do
    def channel_type, do: :fixture
    def capabilities, do: %{}
    def invoke(_, _, _), do: {:error, :unsupported}
    def normalize(_binding, _input, _opts), do: Jido.Chat.Signal.Policy.error(:invalid_delivery)
  end

  setup do
    {:ok, binding} = new_client(FixtureAdapter, id: "telegram-membership", bot_id: 999)
    %{binding: binding}
  end

  defp member(status, extra \\ %{}), do: Map.merge(%{"status" => status, "user" => %{"id" => 42}}, extra)

  defp update(previous, current),
    do: %{
      "chat" => %{"id" => -123},
      "from" => %{"id" => 7},
      "old_chat_member" => previous,
      "new_chat_member" => current
    }

  @cases [
    {"join", "left", "member", %{}, %{}, "joined", "explicit_join", true},
    {"leave", "member", "left", %{}, %{}, "left", "explicit_leave", false},
    {"remove", "member", "kicked", %{}, %{}, "removed", "explicit_remove", false},
    {"promotion", "member", "administrator", %{}, %{}, "role_changed", "state_transition", true},
    {"demotion", "administrator", "member", %{}, %{}, "role_changed", "state_transition", true},
    {"restrict member", "member", "restricted", %{}, %{"is_member" => true}, "restriction_changed", "state_transition",
     true},
    {"restore member", "restricted", "member", %{"is_member" => true}, %{}, "restriction_changed", "state_transition",
     true},
    {"restricted leave", "restricted", "restricted", %{"is_member" => true}, %{"is_member" => false}, "left",
     "explicit_leave", false},
    {"restricted join", "restricted", "restricted", %{"is_member" => false}, %{"is_member" => true}, "joined",
     "explicit_join", true},
    {"permission", "restricted", "restricted", %{"is_member" => true, "can_send_messages" => true},
     %{"is_member" => true, "can_send_messages" => false}, "restriction_changed", "state_transition", true},
    {"reaction permission", "restricted", "restricted", %{"is_member" => true, "can_react_to_messages" => true},
     %{"is_member" => true, "can_react_to_messages" => false}, "restriction_changed", "state_transition", true},
    {"tag permission", "restricted", "restricted", %{"is_member" => true, "can_edit_tag" => true},
     %{"is_member" => true, "can_edit_tag" => false}, "restriction_changed", "state_transition", true},
    {"expiry", "restricted", "restricted", %{"is_member" => true, "until_date" => 0},
     %{"is_member" => true, "until_date" => 100}, "restriction_changed", "state_transition", true},
    {"unchanged", "member", "member", %{}, %{}, "unchanged", "state_transition", true},
    {"unban", "kicked", "left", %{}, %{}, "unknown", "state_transition", false}
  ]

  for {label, old, current, old_extra, extra, transition, evidence, is_member} <- @cases do
    test "#{label} retains exact membership evidence and native JSON identity", context do
      payload =
        update(
          member(unquote(old), unquote(Macro.escape(old_extra))),
          member(unquote(current), unquote(Macro.escape(extra)))
        )

      assert {:ok, signal} = Membership.normalize(context.binding, "update:1", "chat_member", payload)
      assert signal.type == MembershipChanged.type()
      assert signal.data["transition"] == unquote(transition)
      assert signal.data["evidence"] == unquote(evidence)
      assert signal.data["current"]["is_member"] == unquote(is_member)
      assert signal.data["participant_id"] == "42"
      assert signal.data["actor_id"] == "7"
      assert signal.data["bot_self"] == false
      assert signal.source == context.binding.source
      assert signal.subject == Identity.conversation_subject(context.binding.id, "-123")
      catalog = Jido.Signal.Catalog.new!(Jido.Chat.signal_definitions())
      assert {:ok, json} = Jido.Signal.Codec.serialize(signal)
      assert {:ok, ^signal} = Jido.Signal.Catalog.decode(catalog, json)
    end
  end

  test "missing prior state and actor remain explicit partial evidence", context do
    payload = update(nil, member("member")) |> Map.delete("from")
    assert {:ok, signal} = Membership.normalize(context.binding, "update:2", "chat_member", payload)
    assert signal.data["previous"] == nil
    assert signal.data["actor_id"] == nil
    assert signal.data["transition"] == "unknown"
    assert signal.data["evidence"] == "partial_transition"
  end

  test "bot-self is based on update kind or captured bot identity", context do
    payload = update(member("left"), member("member"))
    assert {:ok, self_update} = Membership.normalize(context.binding, "update:3", "my_chat_member", payload)
    assert self_update.data["bot_self"]

    other_bot = put_in(payload, ["new_chat_member", "user"], %{"id" => 42, "is_bot" => true})
    assert {:ok, other} = Membership.normalize(context.binding, "update:3", "chat_member", other_bot)
    refute other.data["bot_self"]

    payload =
      payload |> put_in(["new_chat_member", "user", "id"], 999) |> put_in(["old_chat_member", "user", "id"], 999)

    assert {:ok, captured} = Membership.normalize(context.binding, "update:3", "chat_member", payload)
    assert captured.data["bot_self"]
  end

  test "repeated normalization keeps item identity and projects no private input", context do
    payload =
      update(member("left"), member("member"))
      |> Map.merge(%{"token" => "private-token", "invite_link" => %{pid: self()}})

    assert {:ok, first} = Membership.normalize(context.binding, "update:4", "chat_member", payload)
    assert {:ok, second} = Membership.normalize(context.binding, "update:4", "chat_member", payload)
    assert first.data == second.data
    refute first.id == second.id
    refute Jason.encode!(first.data) =~ "private-token"
  end

  test "atom-key provider maps preserve false member and permission values", context do
    payload = %{
      chat: %{id: -123},
      old_chat_member: %{status: "member", user: %{id: 42}},
      new_chat_member: %{status: "restricted", user: %{id: 42}, is_member: false, can_send_messages: false}
    }

    assert {:ok, signal} = Membership.normalize(context.binding, "update:5", "chat_member", payload)
    assert signal.data["current"]["is_member"] == false
    assert signal.data["current"]["restrictions"]["can_send_messages"] == false
    assert signal.data["transition"] == "left"
  end

  test "invalid or mismatched membership state rejects without raw fallback", context do
    valid = update(member("left"), member("member"))

    for payload <- [
          put_in(valid, ["new_chat_member", "status"], "invalid"),
          put_in(valid, ["new_chat_member", "user", "id"], nil),
          put_in(valid, ["old_chat_member", "user", "id"], 43),
          update(member("member"), member("restricted")),
          update(member("member"), member("restricted", %{"is_member" => "false"})),
          update(member("member"), member("restricted", %{"is_member" => true, "can_send_messages" => self()})),
          update(member("member"), member("restricted", %{"is_member" => true, "until_date" => -1})),
          %{}
        ] do
      assert {:error, %Jido.Chat.Errors.Contract{}} =
               Membership.normalize(context.binding, "update:6", "chat_member", payload)
    end
  end

  defp new_client(adapter, opts) do
    Jido.Chat.Client.new(adapter,
      id: opts[:id],
      credentials: opts |> Keyword.take([:token, :secret_token, :signing_secret]) |> Map.new(),
      transport: opts[:transport] || adapter_transport(adapter),
      config: Keyword.drop(opts, [:id, :token, :secret_token, :signing_secret, :transport])
    )
  end

  defp adapter_transport(adapter) do
    if function_exported?(adapter, :default_transport, 0), do: adapter.default_transport(), else: nil
  end
end
