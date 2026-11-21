defmodule Jido.Chat.Discord.NormalizerTest do
  use ExUnit.Case, async: true
  import Jido.Chat.Discord.Fixtures

  test "Client and discovery perform no I/O and start no Jido process" do
    c = client(fn _, _, _, _ -> flunk("unexpected I/O") end)
    assert c.source == Jido.Chat.Signal.Identity.client_source(c.id)
    refute inspect(c) =~ "test-secret"
    assert Jido.Chat.Discord.adapter() == Jido.Chat.Discord.Adapter
    assert Jido.Chat.Discord.Adapter.default_transport() == Jido.Chat.Discord.Transport.REST
    assert length(Jido.Chat.Discord.operations()) == 3
    assert length(Jido.Chat.Discord.signal_definitions()) == 9
    assert %Jido.Signal.Catalog{} = Jido.Chat.Discord.catalog()
    assert :ok = Jido.Chat.Adapter.validate_capabilities(c.adapter)
    assert c.adapter.capabilities().send_message == :native
    assert c.adapter.capabilities().post_ephemeral == :unsupported
    assert nil == Process.whereis(Jido)
  end

  test "message facts are stable, private, and scoped to the Client" do
    c = client()

    p =
      message(%{
        "timestamp" => ~U[2026-10-18 12:00:00Z],
        "mentions" => [%{"id" => "bot"}],
        "message_reference" => %{"message_id" => 12}
      })

    assert {:ok, d} = Jido.Chat.normalize(c, {:MESSAGE_CREATE, p})
    assert {:ok, second} = Jido.Chat.normalize(c, {:MESSAGE_CREATE, p})
    assert second.id == d.id
    assert hd(second.signals).id == hd(d.signals).id
    assert hd(second.signals).data == hd(d.signals).data
    [s] = d.signals
    assert s.type == "jido.chat.message.received"
    assert s.source == c.source
    assert s.subject == Jido.Chat.Signal.Identity.conversation_subject(c.id, "202")
    assert s.data["sender"]["is_self"] == false
    assert s.data["mentioned"]
    assert s.data["reply_to_id"] == "12"
    assert s.data["timestamp"] == "2026-10-18T12:00:00Z"
    refute Jason.encode!(Jido.Signal.Codec.to_map(s)) =~ "test-secret"
  end

  test "Gateway envelopes, structs, updates, threads and direct messages normalize" do
    c = client()
    p = message(%{"parent_id" => "parent", "author" => %{"id" => "bot", "bot" => true}})
    assert {:ok, %{signals: [thread]}} = Jido.Chat.normalize(c, %{"t" => "MESSAGE_CREATE", "d" => p, "s" => 1})
    assert thread.data["room_id"] == "parent"
    assert thread.data["thread_id"] == "202"
    assert thread.data["sender"]["is_self"]
    assert {:ok, %{signals: [dm]}} = Jido.Chat.normalize(c, message(%{"guild_id" => nil}))
    assert dm.data["conversation_kind"] == "direct"

    assert {:ok, %{signals: [update]}} =
             Jido.Chat.normalize(
               c,
               {:MESSAGE_UPDATE,
                {nil,
                 %{
                   id: 101,
                   channel_id: 202,
                   content: "new",
                   author: %{id: 404},
                   attachments: [],
                   edited_timestamp: "now"
                 }}, %{}}
             )

    assert update.type == "jido.chat.message.updated"
    assert update.data["text"] == "new"
    assert {:ok, %{signals: [_]}} = Jido.Chat.normalize(c, {:MESSAGE_UPDATE, %{id: 101, channel_id: 202}})
  end

  test "attachments use stable references without signed URLs" do
    attachments =
      for {type, index} <- Enum.with_index(["image/png", "audio/ogg", "video/mp4", nil]),
          do: %{id: index, content_type: type, filename: "file", url: "https://cdn.discordapp.com/secret"}

    assert {:ok, %{signals: [s]}} = Jido.Chat.normalize(client(), message(%{"attachments" => attachments}))
    assert Enum.map(s.data["media"], & &1["kind"]) == ~w(image audio video file)

    assert hd(s.data["media"])["resource_ref"] == %{
             "client_id" => "discord-test",
             "kind" => "media",
             "id" => "discord://attachment/202/101/0"
           }

    refute Jason.encode!(Jido.Signal.Codec.to_map(s)) =~ "secret"
  end

  test "delete, reactions and thread facts are catalog valid" do
    c = client()

    cases = [
      {:MESSAGE_DELETE, %{id: 1, channel_id: 2}},
      {:MESSAGE_REACTION_ADD, %{channel_id: 2, message_id: 1, user_id: 3, emoji: %{name: "yes", id: 9}}},
      {:MESSAGE_REACTION_REMOVE, %{channel_id: 2, message_id: 1, user_id: 3, emoji: %{name: "👍"}}},
      {:THREAD_CREATE, %{id: 4, parent_id: 2, name: "thread", owner_id: 3}}
    ]

    assert {:ok, %{signals: signals}} = Jido.Chat.normalize(c, cases)

    assert Enum.map(signals, & &1.type) ==
             ~w(jido.chat.message.deleted jido.chat.reaction.added jido.chat.reaction.removed jido.chat.thread.started)

    assert Enum.at(signals, 1).data["reaction"] == "yes:9"
  end

  test "interactions preserve public facts and omit private tokens" do
    c = client()
    base = %{id: 1, channel_id: 2, token: "private", member: %{user: %{id: 3}}}

    inputs = [
      Map.merge(base, %{type: 1}),
      Map.merge(base, %{type: 2, data: %{name: "hello", options: [%{value: "world"}]}}),
      Map.merge(base, %{type: 3, data: %{custom_id: "pick", values: ["a"]}, message: %{id: 4}}),
      Map.merge(base, %{
        type: 5,
        data: %{custom_id: "modal", components: [%{components: [%{custom_id: "field", value: "answer"}]}]}
      })
    ]

    assert {:ok, %{signals: [slash, action, modal]} = delivery} =
             Jido.Chat.normalize(c, Enum.map(inputs, &{:INTERACTION_CREATE, &1}))

    assert slash.data["command"] == "/hello"
    assert slash.data["text"] == "world"
    assert action.data["values"] == %{"pick" => ["a"]}
    assert modal.data["values"] == %{"field" => "answer"}
    refute inspect(delivery) =~ "private"
  end

  test "bad and unsupported items produce bounded failure facts" do
    for input <- [
          nil,
          42,
          {:UNKNOWN, %{}},
          {:INTERACTION_CREATE, %{type: 8}},
          {:MESSAGE_CREATE, %{}},
          {:MESSAGE_CREATE, nil}
        ] do
      assert {:ok, %{signals: [failure]}} = Jido.Chat.normalize(client(), input)
      assert failure.type == "jido.chat.normalization.failed"
    end

    assert {:ok, %{signals: []}} = Jido.Chat.normalize(client(), [])
    assert {:error, _} = Jido.Chat.normalize(client(), List.duplicate(nil, 21))
  end

  test "one malformed item does not discard a valid item" do
    assert {:ok, %{signals: [received, failure]}} =
             Jido.Chat.normalize(client(), [message(), message(%{"attachments" => "invalid"})])

    assert received.type == "jido.chat.message.received"
    assert failure.type == "jido.chat.normalization.failed"
    assert {:ok, %{signals: [_]}} = Jido.Chat.normalize(client(), %{event: :message_create, payload: message()})
  end
end
