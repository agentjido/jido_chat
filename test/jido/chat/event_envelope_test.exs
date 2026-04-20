defmodule Jido.Chat.EventEnvelopeTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{
    ActionEvent,
    AssistantContextChangedEvent,
    AssistantThreadStartedEvent,
    EventEnvelope,
    EventNormalizer,
    Incoming,
    ModalCloseEvent,
    ModalSubmitEvent,
    ReactionEvent,
    SlashCommandEvent
  }

  test "event envelope round-trips each supported payload type" do
    payloads = [
      {:message,
       Incoming.new(%{external_room_id: "room-1", external_message_id: "msg-1", text: "hi"})},
      {:reaction, ReactionEvent.new(%{emoji: "👍", message_id: "msg-1"})},
      {:action, ActionEvent.new(%{action_id: "approve", message_id: "msg-2"})},
      {:modal_submit, ModalSubmitEvent.new(%{callback_id: "deploy", values: %{env: "prod"}})},
      {:modal_close, ModalCloseEvent.new(%{callback_id: "deploy"})},
      {:slash_command, SlashCommandEvent.new(%{command: "/deploy", text: "prod"})},
      {:assistant_thread_started, AssistantThreadStartedEvent.new(%{thread_id: "thr-1"})},
      {:assistant_context_changed,
       AssistantContextChangedEvent.new(%{thread_id: "thr-1", context: %{a: 1}})}
    ]

    for {event_type, payload} <- payloads do
      envelope =
        EventEnvelope.new(%{
          adapter_name: :telegram,
          event_type: event_type,
          payload: payload,
          raw: %{"source" => "test"}
        })

      round_tripped = envelope |> EventEnvelope.to_map() |> EventEnvelope.from_map()

      assert round_tripped.event_type == event_type
      assert round_tripped.adapter_name == :telegram
      assert round_tripped.raw == %{"source" => "test"}
      assert round_tripped.payload.__struct__ == payload.__struct__
    end
  end

  test "event envelope normalizes string event types and infers missing event types" do
    reaction_envelope =
      EventEnvelope.new(%{
        adapter_name: :discord,
        event_type: "reaction",
        payload: ReactionEvent.new(%{emoji: "🔥", message_id: "msg-9"})
      })

    assert reaction_envelope.event_type == :reaction

    assert {:ok, inferred} =
             EventNormalizer.ensure_event_envelope(
               %{payload: %{emoji: "🔥", message_id: "msg-9"}},
               :discord
             )

    assert inferred.event_type == :reaction
    assert inferred.adapter_name == :discord
  end

  test "event normalizer enriches payload-derived ids and normalizes event user maps" do
    assert {:ok, reaction} =
             EventNormalizer.ensure_reaction_event(
               %{
                 emoji: "👍",
                 thread_id: "thread-1",
                 channel_id: "chan-1",
                 message_id: "msg-1",
                 user: %{id: "user-1", username: "casey", name: "Casey"}
               },
               :slack
             )

    assert reaction.adapter_name == :slack
    assert reaction.user.user_id == "user-1"
    assert reaction.user.user_name == "casey"
    assert reaction.user.full_name == "Casey"

    envelope =
      EventEnvelope.new(%{adapter_name: :telegram, event_type: :message, payload: nil})
      |> EventNormalizer.with_envelope_payload(
        Incoming.new(%{
          external_room_id: "room-42",
          external_thread_id: "thread-77",
          external_message_id: "msg-88",
          text: "hello"
        })
      )

    assert envelope.thread_id == "telegram:room-42:thread-77"
    assert envelope.channel_id == "room-42"
    assert envelope.message_id == "msg-88"
  end

  test "event normalizer returns tagged errors for invalid inputs" do
    assert {:error, {:invalid_incoming, :bad}} = EventNormalizer.ensure_incoming(:bad)

    assert {:error, {:invalid_reaction_event, :bad}} =
             EventNormalizer.ensure_reaction_event(:bad, :slack)

    assert {:error, {:invalid_event_envelope, :bad}} =
             EventNormalizer.ensure_event_envelope(:bad, :slack)
  end
end
