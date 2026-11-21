defmodule Jido.Chat.Telegram.NormalizerTest do
  use ExUnit.Case, async: true
  alias Jido.Chat.Delivery
  alias Jido.Chat.Signal.Identity
  alias Jido.Chat.Telegram.Adapter

  setup do
    {:ok, binding} = new_client(Adapter, id: "normalizer", token: "fixture-token", bot_id: 99, bot_username: "bot")
    %{binding: binding}
  end

  defp message(extra \\ %{}) do
    Map.merge(
      %{
        "message_id" => 7,
        "chat" => %{"id" => -123, "type" => "supergroup", "title" => "Group"},
        "from" => %{"id" => 42, "username" => "peer", "first_name" => "Peer", "last_name" => "Name"},
        "text" => "hello",
        "date" => 100
      },
      extra
    )
  end

  defp update(id \\ 10, extra \\ %{}), do: Map.merge(%{"update_id" => id, "message" => message()}, extra)

  defp normalized(binding, input) do
    assert {:ok, %Delivery{} = delivery} = Jido.Chat.normalize(binding, input)
    catalog = Jido.Signal.Catalog.new!(Jido.Chat.signal_definitions())

    for signal <- delivery.signals do
      assert signal.source == binding.source
      assert {:ok, json} = Jido.Signal.Codec.serialize(signal)
      assert {:ok, ^signal} = Jido.Signal.Catalog.decode(catalog, json)
      refute Map.has_key?(signal.data, "raw")
    end

    delivery
  end

  test "empty units remain valid and ordered batches retain every message", %{binding: binding} do
    assert normalized(binding, []).signals == []
    assert normalized(binding, %{"update_id" => 1}).signals == []
    unit = normalized(binding, [update(1), update(2), update(3)])
    assert Enum.map(unit.signals, & &1.data["item_id"]) == Enum.map(1..3, &"telegram:update:#{&1}:message")
    assert Enum.all?(unit.signals, &(&1.data["delivery_id"] == unit.id))
  end

  test "webhook and polling share item identity without sharing a batch identity", %{binding: binding} do
    single = normalized(binding, update())
    batch = normalized(binding, [update()])
    assert single.id != batch.id
    assert hd(single.signals).data["item_id"] == hd(batch.signals).data["item_id"]
    assert hd(single.signals).subject == Identity.conversation_subject(binding.id, "-123")
  end

  test "message projection retains sender, thread, full text, reply and conversation data", %{binding: binding} do
    payload =
      update(10, %{
        "message" =>
          message(%{
            "message_thread_id" => 8,
            "reply_to_message" => %{"message_id" => 6, "text" => "prior", "from" => %{"id" => 11}},
            "token" => "private-token",
            "private" => self()
          })
      })

    [fact] = normalized(binding, payload).signals
    assert fact.type == "jido.chat.message.received"
    assert fact.data["text"] == "hello"
    assert fact.data["thread_id"] == "8"
    assert fact.data["reply_to_id"] == "6"
    assert fact.data["reply_context"]["sender"]["id"] == "11"
    assert fact.data["sender"]["display_name"] == "Peer Name"
    assert fact.data["conversation_kind"] == "group"
    assert fact.data["conversation_name"] == "Group"
    refute Jason.encode!(fact.data) =~ "private-token"
  end

  test "edited messages and edited channel posts are update facts", %{binding: binding} do
    for kind <- ~w(edited_message edited_channel_post) do
      [fact] = normalized(binding, %{"update_id" => 20, kind => message(%{"edit_date" => 200})}).signals
      assert fact.type == "jido.chat.message.updated"
      assert fact.data["text"] == "hello"
      assert fact.data["timestamp"] == "1970-01-01T00:03:20Z"
    end
  end

  test "slash commands preserve the complete message and a separate command fact", %{binding: binding} do
    [received, command] =
      normalized(binding, update(10, %{"message" => message(%{"text" => "/hello@bot some arguments"})})).signals

    assert received.data["text"] == "/hello@bot some arguments"
    assert command.type == "jido.chat.slash_command.received"
    assert command.data["command"] == "hello"
    assert command.data["text"] == "some arguments"
  end

  test "UTF-16 mention offsets retain the provider text and target", %{binding: binding} do
    payload =
      update(10, %{
        "message" =>
          message(%{"text" => "😀 @bot hello", "entities" => [%{"type" => "mention", "offset" => 3, "length" => 4}]})
      })

    [fact] = normalized(binding, payload).signals
    assert fact.data["mentioned"]
    assert fact.data["mentions"] == ["@bot"]
    assert fact.data["mention_details"] == [%{"id" => "@bot", "username" => "@bot", "offset" => 3, "length" => 4}]
  end

  test "membership keeps restricted is_member and item identity across both transports", %{binding: binding} do
    member = %{"status" => "restricted", "is_member" => false, "user" => %{"id" => 42}}

    payload = %{
      "update_id" => 10,
      "chat_member" => %{
        "chat" => %{"id" => -123},
        "old_chat_member" => %{"status" => "member", "user" => %{"id" => 42}},
        "new_chat_member" => member
      }
    }

    [fact] = normalized(binding, payload).signals
    [polled] = normalized(binding, [payload]).signals
    assert fact.type == "jido.chat.membership.changed"
    assert fact.data["transition"] == "left"
    assert fact.data["current"]["is_member"] == false
    assert fact.data["item_id"] == polled.data["item_id"]
  end

  test "a membership service message retains every joined member without a message fact", %{binding: binding} do
    payload =
      update(10, %{"message" => message(%{"new_chat_members" => [%{"id" => 41}, %{"id" => 42}, %{"id" => 99}]})})

    facts = normalized(binding, payload).signals
    assert Enum.map(facts, & &1.data["participant_id"]) == ["41", "42", "99"]
    assert Enum.all?(facts, &(&1.type == "jido.chat.membership.changed"))
    assert List.last(facts).data["bot_self"]
  end

  test "reaction changes retain every removal and addition in order", %{binding: binding} do
    reaction = fn emoji -> %{"type" => "emoji", "emoji" => emoji} end

    payload = %{
      "update_id" => 10,
      "message_reaction" => %{
        "chat" => %{"id" => -123},
        "message_id" => 7,
        "user" => %{"id" => 42},
        "old_reaction" => Enum.map(["A", "B"], reaction),
        "new_reaction" => Enum.map(["B", "C", "D"], reaction)
      }
    }

    facts = normalized(binding, payload).signals

    assert Enum.map(facts, &{&1.type, &1.data["reaction"]}) == [
             {"jido.chat.reaction.removed", "A"},
             {"jido.chat.reaction.added", "C"},
             {"jido.chat.reaction.added", "D"}
           ]
  end

  test "callback queries select portable interaction data", %{binding: binding} do
    payload = %{
      "update_id" => 10,
      "callback_query" => %{
        "id" => "callback",
        "data" => "confirm",
        "from" => %{"id" => 42},
        "message" => message(),
        "token" => "private-token"
      }
    }

    [fact] = normalized(binding, payload).signals
    assert fact.type == "jido.chat.action.received"
    assert fact.data["interaction_id"] == "callback"
    assert fact.data["value"] == "confirm"
    refute Jason.encode!(fact.data) =~ "private-token"
  end

  test "media facts preserve dimensions, duration, and false sticker flags from ExGram structs", %{binding: binding} do
    for kind <- ["message", "edited_message"] do
      note = %ExGram.Model.VideoNote{file_id: "note", length: 240, duration: 1}

      raw = %ExGram.Model.Message{
        message_id: 7,
        chat: %ExGram.Model.Chat{id: -123, type: "supergroup"},
        from: %ExGram.Model.User{id: 42, is_bot: false, first_name: "Peer"},
        video_note: note
      }

      [fact] = normalized(binding, %{"update_id" => 10, kind => raw}).signals
      assert fact.type == if(kind == "message", do: "jido.chat.message.received", else: "jido.chat.message.updated")
      assert [%{"width" => 240, "height" => 240, "duration" => 1, "media_type" => "video/mp4"}] = fact.data["media"]
    end

    sticker = %ExGram.Model.Sticker{file_id: "sticker", width: 512, height: 512, is_animated: false, is_video: false}
    [fact] = normalized(binding, update(10, %{"message" => message(%{"sticker" => sticker})})).signals
    assert [media] = fact.data["media"]
    assert media["metadata"] == %{"telegram" => %{"is_animated" => false, "is_video" => false}}
  end

  test "malformed items produce registered failures between valid messages", %{binding: binding} do
    facts = normalized(binding, [update(1), %{"update_id" => 2, "message" => %{}}, update(3)]).signals

    assert Enum.map(facts, & &1.type) == [
             "jido.chat.message.received",
             "jido.chat.normalization.failed",
             "jido.chat.message.received"
           ]

    assert Enum.at(facts, 1).data["code"] == "invalid_item"
    assert Enum.at(facts, 1).data["item_index"] == 1
  end

  test "missing provider IDs use a stable canonical digest for atom or string keys", %{binding: binding} do
    string = normalized(binding, %{"message" => message()})
    atom = normalized(binding, %{message: message()})
    assert string.id == atom.id
    assert hd(string.signals).data["item_id"] == hd(atom.signals).data["item_id"]
  end

  test "size, count and failure limits reject the complete batch", %{binding: binding} do
    for {input, code} <- [
          {Enum.map(1..101, &update/1), :too_many_signals},
          {Enum.map(1..21, &%{"update_id" => &1, "message" => %{}}), :too_many_failures},
          {update(1, %{"message" => message(%{"text" => String.duplicate("x", 262_144)})}), :signal_too_large},
          {Enum.map(1..6, &update(&1, %{"message" => message(%{"text" => String.duplicate("x", 200_000)})})),
           :delivery_too_large}
        ] do
      assert {:error, %Jido.Chat.Errors.Contract{code: ^code}} = Jido.Chat.normalize(binding, input)
    end
  end

  test "blank or non-string photo MIME values retain the JPEG provider fallback", %{binding: binding} do
    for mime <- [nil, "", " \t\n", 123] do
      [fact] =
        normalized(
          binding,
          update(10, %{"message" => message(%{"photo" => [%{"file_id" => "photo", "mime_type" => mime}]})})
        ).signals

      assert hd(fact.data["media"])["media_type"] == "image/jpeg"
    end
  end

  test "a channel post without a user sender uses the provider channel identity", %{binding: binding} do
    channel = message(%{"chat" => %{"id" => -123, "type" => "channel", "title" => "Publisher"}}) |> Map.delete("from")
    [fact] = normalized(binding, %{"update_id" => 10, "channel_post" => channel}).signals
    assert fact.data["sender"]["id"] == "-123"
    assert fact.data["conversation_kind"] == "channel"
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
