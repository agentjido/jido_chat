defmodule Jido.Chat.Slack.NormalizerTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Slack.Adapter

  defp client do
    Jido.Chat.Client.new!(Adapter,
      id: "slack-normalizer",
      credentials: %{bot_token: "xoxb-private"},
      config: [bot_user_id: "UBOT"]
    )
  end

  defp event(type, overrides) do
    %{
      "type" => "event_callback",
      "event_id" => "Ev1",
      "event" =>
        Map.merge(
          %{"type" => type, "channel" => "C1", "user" => "U1", "ts" => "1700000000.000001"},
          overrides
        )
    }
  end

  test "message facts are stable, client scoped, and contain no credential" do
    payload =
      event("message", %{
        "text" => "hello <@UBOT>",
        "files" => [
          %{
            "id" => "F1",
            "name" => "image.png",
            "mimetype" => "image/png",
            "url_private" => "https://files.slack.com/F1",
            "original_w" => 10,
            "original_h" => 20
          }
        ]
      })

    assert {:ok, first} = Jido.Chat.normalize(client(), payload)
    assert {:ok, second} = Jido.Chat.normalize(client(), payload)
    assert first.id == second.id
    assert Enum.map(first.signals, &{&1.id, &1.data}) == Enum.map(second.signals, &{&1.id, &1.data})
    [signal] = first.signals
    assert signal.type == "jido.chat.message.received"
    assert signal.subject == Jido.Chat.Signal.Identity.conversation_subject("slack-normalizer", "C1")
    assert signal.data["mentions"] == ["UBOT"]
    assert signal.data["mentioned"]
    assert signal.data["media"] |> hd() |> Map.take(["kind", "name"]) == %{"kind" => "image", "name" => "image.png"}
    refute Jason.encode!(Jido.Signal.Codec.to_map(signal)) =~ "xoxb-private"
  end

  test "message updates, deletes, and reactions map to core facts" do
    inputs = [
      event("message", %{
        "subtype" => "message_changed",
        "message" => %{"ts" => "M1", "user" => "U1", "text" => "new", "edited" => %{"ts" => "1700000001.0"}}
      }),
      event("message", %{
        "subtype" => "message_deleted",
        "deleted_ts" => "M2",
        "previous_message" => %{"ts" => "M2", "user" => "U2"}
      }),
      event("reaction_added", %{"user" => "U3", "reaction" => "eyes", "item" => %{"channel" => "C1", "ts" => "M1"}}),
      event("reaction_removed", %{"user" => "U3", "reaction" => "eyes", "item" => %{"channel" => "C1", "ts" => "M1"}})
    ]

    assert {:ok, delivery} = Jido.Chat.normalize(client(), inputs)

    assert Enum.map(delivery.signals, & &1.type) ==
             ~w(jido.chat.message.updated jido.chat.message.deleted jido.chat.reaction.added jido.chat.reaction.removed)

    assert Enum.at(delivery.signals, 0).data["text"] == "new"
    assert Enum.at(delivery.signals, 1).data["message_id"] == "M2"
    assert Enum.at(delivery.signals, 2).data["reaction"] == "eyes"
  end

  test "slash commands and block actions map public interaction data" do
    slash = %{
      "command" => "/ask",
      "text" => "hello",
      "channel_id" => "C1",
      "user_id" => "U1",
      "trigger_id" => "TR1",
      "response_url" => "https://hooks.slack.com/private"
    }

    action = %{
      "type" => "block_actions",
      "trigger_id" => "TR2",
      "channel" => %{"id" => "C1"},
      "user" => %{"id" => "U1"},
      "message" => %{"ts" => "M1"},
      "actions" => [
        %{"action_id" => "approve", "value" => "yes"},
        %{"action_id" => "pick", "selected_options" => [%{"value" => "a"}, %{"value" => "b"}]}
      ]
    }

    assert {:ok, delivery} = Jido.Chat.normalize(client(), [slash, action])
    [command, first, second] = delivery.signals
    assert command.type == "jido.chat.slash_command.received"
    assert command.data["command"] == "/ask"
    assert first.data["values"] == %{"approve" => "yes"}
    assert second.data["values"] == %{"pick" => ["a", "b"]}
    refute inspect(delivery) =~ "hooks.slack.com"
  end

  test "modal submission, close, and option requests map through private metadata" do
    base = %{
      "user" => %{"id" => "U1"},
      "view" => %{"id" => "V1", "callback_id" => "survey", "private_metadata" => Jason.encode!(%{"room_id" => "C1"})}
    }

    submission =
      base
      |> Map.put("type", "view_submission")
      |> put_in(["view", "state"], %{
        "values" => %{"block" => %{"name" => %{"type" => "plain_text_input", "value" => "Ada"}}}
      })

    closed = Map.put(base, "type", "view_closed")

    options = %{
      "type" => "block_suggestion",
      "user" => %{"id" => "U1"},
      "view" => base["view"],
      "action_id" => "search",
      "value" => "ad"
    }

    assert {:ok, delivery} = Jido.Chat.normalize(client(), [submission, closed, options])
    [submitted, modal_closed, requested] = delivery.signals
    assert submitted.data["values"] == %{"block.name" => "Ada"}
    assert modal_closed.type == "jido.chat.modal.closed"
    assert requested.data["query"] == "ad"
    assert Enum.all?(delivery.signals, &(&1.data["room_id"] == "C1"))
  end

  test "invalid and unsupported items become bounded failure facts" do
    for input <- [
          nil,
          %{},
          %{"type" => "url_verification", "challenge" => "private"},
          event("message", %{"user" => nil})
        ] do
      assert {:ok, %{signals: [failure]}} = Jido.Chat.normalize(client(), input)
      assert failure.type == "jido.chat.normalization.failed"
    end

    assert {:ok, %{signals: []}} = Jido.Chat.normalize(client(), [])
    assert {:error, _} = Jido.Chat.normalize(client(), List.duplicate(nil, 21))
  end

  test "a Slack file without a private download URL does not discard its message" do
    payload = event("message", %{"text" => "file pending", "files" => [%{"id" => "F1", "name" => "pending"}]})
    assert {:ok, %{signals: [signal]}} = Jido.Chat.normalize(client(), payload)
    assert signal.type == "jido.chat.message.received"
    assert signal.data["media"] == []
  end
end
