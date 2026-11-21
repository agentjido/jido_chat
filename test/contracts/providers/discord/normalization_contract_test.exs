defmodule Jido.Chat.Discord.NormalizationContractTest do
  use Covenant.Case, component: "jido_chat_discord.normalization", async: true
  import Jido.Chat.Discord.Fixtures
  alias Jido.Chat

  @tag obligation: "jido_chat_discord.normalization.I1"
  test "fixed message reaction delete and thread events produce scoped catalog facts" do
    c = client()

    for {event, type, expected} <- [
          {{:MESSAGE_CREATE, message()}, "jido.chat.message.received",
           %{"message_id" => "101", "room_id" => "202", "text" => "hello"}},
          {{:MESSAGE_UPDATE, message(%{"content" => "edited"})}, "jido.chat.message.updated",
           %{"message_id" => "101", "text" => "edited"}},
          {{:MESSAGE_DELETE, %{"id" => "101", "channel_id" => "202"}}, "jido.chat.message.deleted",
           %{"message_id" => "101"}},
          {{:MESSAGE_REACTION_ADD,
            %{"message_id" => "101", "channel_id" => "202", "user_id" => "404", "emoji" => %{"name" => "ok"}}},
           "jido.chat.reaction.added", %{"message_id" => "101", "reaction" => "ok"}},
          {{:MESSAGE_REACTION_REMOVE,
            %{"message_id" => "101", "channel_id" => "202", "user_id" => "404", "emoji" => %{"name" => "ok"}}},
           "jido.chat.reaction.removed", %{"message_id" => "101"}},
          {{:THREAD_CREATE, %{"id" => "555", "parent_id" => "202", "name" => "thread", "owner_id" => "404"}},
           "jido.chat.thread.started", %{"thread_id" => "555", "room_id" => "202"}}
        ] do
      assert {:ok, %{signals: [fact]} = delivery} = Chat.normalize(c, event)
      assert {:ok, repeated} = Chat.normalize(c, event)
      assert repeated.id == delivery.id
      assert Enum.map(repeated.signals, &{&1.id, &1.data}) == Enum.map(delivery.signals, &{&1.id, &1.data})
      assert fact.type == type
      assert %Jido.Trace{} = Jido.Signal.Context.get_trace(fact)
      assert Map.take(fact.data, Map.keys(expected)) == expected
      assert fact.source == c.source
      assert fact.subject == Chat.Signal.Identity.conversation_subject(c.id, "202")
      assert {:ok, _} = Jido.Signal.Catalog.validate(Chat.catalog(c), fact)
    end
  end

  @tag obligation: "jido_chat_discord.normalization.I2"
  test "slash component and modal input drops private controls" do
    c = client()
    secret = Base.encode64(:crypto.strong_rand_bytes(24))

    base = %{
      "id" => "909",
      "application_id" => "bot",
      "channel_id" => "202",
      "token" => secret,
      "member" => %{"user" => %{"id" => "404"}}
    }

    for {kind, data, type, expected} <- [
          {2, %{"name" => "proof", "options" => [%{"name" => "value", "value" => "hello"}]},
           "jido.chat.slash_command.received", %{"command" => "/proof", "text" => "hello"}},
          {3, %{"custom_id" => "proof", "values" => ["chosen"]}, "jido.chat.action.received",
           %{"action_id" => "proof", "value" => "chosen"}},
          {5,
           %{
             "custom_id" => "proof",
             "components" => [%{"components" => [%{"custom_id" => "answer", "value" => "hello"}]}]
           }, "jido.chat.modal.submitted", %{"callback_id" => "proof", "values" => %{"answer" => "hello"}}}
        ] do
      input = {:INTERACTION_CREATE, Map.merge(base, %{"type" => kind, "data" => data})}
      assert {:ok, %{signals: [fact]}} = Chat.normalize(c, input)
      assert fact.type == type
      assert Map.take(fact.data, Map.keys(expected)) == expected
      assert fact.data["interaction_id"] == "909"
      refute Jason.encode!(Jido.Signal.Codec.to_map(fact)) =~ secret
      refute Map.has_key?(fact.data, "raw")
      assert {:ok, _} = Jido.Signal.Catalog.validate(Chat.catalog(c), fact)
    end
  end

  @tag obligation: "jido_chat_discord.normalization.I3"
  test "fixed media projection uses a stable scoped reference" do
    input =
      message(%{
        "attachments" => [
          %{
            "id" => "9",
            "filename" => "proof.png",
            "content_type" => "image/png",
            "width" => 20,
            "height" => 10,
            "url" => "https://cdn.discordapp.com/private-signed"
          }
        ]
      })

    assert {:ok, %{signals: [fact]}} = Chat.normalize(client(), input)
    [media] = fact.data["media"]

    assert media["resource_ref"] == %{
             "client_id" => "discord-test",
             "kind" => "media",
             "id" => "discord://attachment/202/101/9"
           }

    assert media["kind"] == "image"
    refute Jason.encode!(Jido.Signal.Codec.to_map(fact)) =~ "private-signed"
  end

  @tag obligation: "jido_chat_discord.normalization.I4"
  test "malformed siblings produce safe failures without dropping good input" do
    input = [message(), :malformed, message(%{"id" => "102"})]
    assert {:ok, %{signals: [first, failure, last]} = delivery} = Chat.normalize(client(), input)
    assert first.data["message_id"] == "101"
    assert last.data["message_id"] == "102"
    assert failure.type == "jido.chat.normalization.failed"
    assert failure.data["item_index"] == 1
    assert {:ok, repeated} = Chat.normalize(client(), input)
    assert repeated.id == delivery.id
    assert Enum.map(repeated.signals, &{&1.id, &1.data}) == Enum.map(delivery.signals, &{&1.id, &1.data})

    for fact <- delivery.signals do
      assert {:ok, _} = Jido.Signal.Catalog.validate(Chat.Discord.catalog(), fact)
    end
  end
end
