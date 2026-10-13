defmodule Jido.Chat.AdapterPairConformanceTest do
  use ExUnit.Case, async: true

  @matrix Path.expand("../../docs/migration/adapter-matrix.json", __DIR__)
          |> File.read!()
          |> Jason.decode!()

  defmodule NoTransport do
    def call(_, _, _, _), do: raise("unexpected provider call")
  end

  defp new_binding("jido_chat_telegram") do
    Jido.Chat.bind(Jido.Chat.Telegram.Adapter,
      id: "telegram-pair",
      token: "fixture-token",
      bot_id: 99,
      transport: NoTransport
    )
  end

  defp new_binding("jido_chat_slack") do
    Jido.Chat.bind(Jido.Chat.Slack.Adapter,
      id: "slack-pair",
      token: "fixture-token",
      bot_user_id: "UBOT",
      transport: NoTransport
    )
  end

  defp telegram_message do
    %{"message_id" => 1, "chat" => %{"id" => 123, "type" => "group"}, "from" => %{"id" => 42}, "text" => "hello"}
  end

  defp telegram_fixture(name) do
    message = telegram_message()
    reaction = %{"chat" => %{"id" => 123}, "message_id" => 1, "user" => %{"id" => 42}}

    item =
      case name do
        "MessageReceived" ->
          %{"message" => message}

        "MessageUpdated" ->
          %{"edited_message" => message}

        "ReactionAdded" ->
          %{
            "message_reaction" =>
              Map.merge(reaction, %{"old_reaction" => [], "new_reaction" => [%{"type" => "emoji", "emoji" => "👍"}]})
          }

        "ReactionRemoved" ->
          %{
            "message_reaction" =>
              Map.merge(reaction, %{"old_reaction" => [%{"type" => "emoji", "emoji" => "👍"}], "new_reaction" => []})
          }

        "ActionReceived" ->
          %{"callback_query" => %{"id" => "Q1", "data" => "confirm", "from" => %{"id" => 42}, "message" => message}}

        "SlashCommandReceived" ->
          %{
            "message" =>
              Map.merge(message, %{
                "text" => "/help args",
                "entities" => [%{"type" => "bot_command", "offset" => 0, "length" => 5}]
              })
          }

        "MembershipChanged" ->
          %{
            "chat_member" => %{
              "chat" => %{"id" => 123},
              "old_chat_member" => %{"status" => "left", "user" => %{"id" => 42}},
              "new_chat_member" => %{"status" => "member", "user" => %{"id" => 42}}
            }
          }

        _ ->
          %{Macro.underscore(name) => %{}}
      end

    Map.put(item, "update_id", 10)
  end

  defp slack_fixture(name) do
    message = %{"type" => "message", "channel" => "C1", "user" => "U1", "ts" => "1.01", "text" => "hello"}
    view = %{"id" => "V1", "private_metadata" => Jason.encode!(%{"channel_id" => "C1"}), "state" => %{"values" => %{}}}

    case name do
      "MessageReceived" ->
        message

      "MessageUpdated" ->
        %{"type" => "message", "subtype" => "message_changed", "channel" => "C1", "message" => message}

      "MessageDeleted" ->
        %{"type" => "message", "subtype" => "message_deleted", "channel" => "C1", "deleted_ts" => "1.01"}

      "ReactionAdded" ->
        %{
          "type" => "reaction_added",
          "reaction" => "thumbsup",
          "user" => "U1",
          "item" => %{"channel" => "C1", "ts" => "1.01"}
        }

      "ReactionRemoved" ->
        %{
          "type" => "reaction_removed",
          "reaction" => "thumbsup",
          "user" => "U1",
          "item" => %{"channel" => "C1", "ts" => "1.01"}
        }

      "ActionReceived" ->
        %{
          "type" => "block_actions",
          "channel" => %{"id" => "C1"},
          "trigger_id" => "private-trigger",
          "actions" => [%{"action_id" => "confirm"}]
        }

      "ModalSubmitted" ->
        %{"type" => "view_submission", "view" => view}

      "ModalClosed" ->
        %{"type" => "view_closed", "view" => view}

      "OptionsRequested" ->
        %{"type" => "block_suggestion", "channel" => %{"id" => "C1"}, "action_id" => "select", "value" => "query"}

      "SlashCommandReceived" ->
        %{
          "command" => "/help",
          "channel_id" => "C1",
          "user_id" => "U1",
          "text" => "args",
          "trigger_id" => "private-trigger"
        }

      "AssistantThreadStarted" ->
        %{
          "type" => "assistant_thread_started",
          "assistant_thread" => %{"channel_id" => "C1", "thread_ts" => "1.01", "user_id" => "U1", "context" => %{}}
        }

      "AssistantContextChanged" ->
        %{
          "type" => "assistant_thread_context_changed",
          "assistant_thread" => %{"channel_id" => "C1", "thread_ts" => "1.01", "user_id" => "U1", "context" => %{}}
        }

      "MembershipChanged" ->
        %{"type" => "member_joined_channel", "channel" => "C1", "user" => "U1"}

      _ ->
        %{"type" => Macro.underscore(name), "channel" => "C1"}
    end
  end

  defp forms("jido_chat_telegram", payload),
    do: [payload, Jido.Chat.WebhookRequest.new(%{payload: payload}), [payload]]

  defp forms("jido_chat_slack", payload),
    do: [
      payload,
      Jason.encode!(payload),
      URI.encode_query(%{"payload" => Jason.encode!(payload)}),
      Jido.Chat.WebhookRequest.new(%{payload: payload}),
      %{"type" => "events_api", "envelope_id" => "E1", "payload" => payload}
    ]

  for row <- @matrix["adapters"], row["package"] in ~w(jido_chat_telegram jido_chat_slack) do
    package = row["package"]

    test "#{package} capabilities match every frozen operation and participant row" do
      {:ok, binding} = new_binding(unquote(package))
      actual = Jido.Chat.Adapter.capabilities(binding.adapter)
      expected = unquote(Macro.escape(row["operation_support"]))
      assert map_size(expected) == 26

      for {operation, status} <- expected do
        assert actual[String.to_existing_atom(operation)] == String.to_existing_atom(status)
      end

      assert to_string(actual[:get_thread_participants]) == unquote(row["participant_query_support"])
      refute unquote(row["participant_query_complete"])
    end

    for {name, support} <- row["event_support"] do
      test "#{package} #{name} matches frozen #{support} support in every declared form" do
        package = unquote(package)
        name = unquote(name)
        {:ok, binding} = new_binding(package)
        payload = if package == "jido_chat_telegram", do: telegram_fixture(name), else: slack_fixture(name)
        type = Module.concat(Jido.Chat.Signal, name).type()
        catalog = Jido.Signal.Catalog.new!(Jido.Chat.signal_definitions())

        deliveries =
          for input <- forms(package, payload) do
            assert {:ok, %Jido.Chat.Delivery{} = delivery} = Jido.Chat.normalize_event(binding, input)

            expected =
              cond do
                unquote(support) == "unsupported" ->
                  [Jido.Chat.Signal.NormalizationFailed.type()]

                package == "jido_chat_telegram" and name == "SlashCommandReceived" ->
                  [Jido.Chat.Signal.MessageReceived.type(), type]

                true ->
                  [type]
              end

            assert Enum.map(delivery.signals, & &1.type) == expected

            for fact <- delivery.signals do
              assert fact.source == binding.source
              assert {:ok, json} = Jido.Signal.Serialization.serialize(fact)
              assert {:ok, ^fact} = Jido.Signal.Catalog.decode(catalog, json)
              refute json =~ "fixture-token"
              refute json =~ "private-trigger"

              if unquote(support) == "unsupported", do: assert(fact.data["code"] == "unsupported_item")
            end

            delivery
          end

        assert length(Enum.uniq(Enum.map(deliveries, &Enum.map(&1.signals, fn fact -> fact.data["item_id"] end)))) == 1
      end
    end
  end
end
