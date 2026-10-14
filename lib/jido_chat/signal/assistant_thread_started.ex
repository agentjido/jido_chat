defmodule Jido.Chat.Signal.AssistantThreadStarted do
  @moduledoc """
  Typed fact definition for `jido.chat.assistant.thread_started`.

  Data uses the protocol version 1 string-key schema. The binding-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :fact,
    type: "jido.chat.assistant.thread_started",
    dataschema: "urn:jido:chat:schema:assistant_thread_started:1",
    default_source: "urn:jido:chat:binding:YmluZGluZy9hbHBoYQ",
    schema:
      Zoi.map(
        %{
          "item_id" => Zoi.string() |> Zoi.min(1),
          "delivery_id" => Zoi.string() |> Zoi.min(1),
          "room_id" => Zoi.string() |> Zoi.min(1),
          "thread_id" => Zoi.string() |> Zoi.min(1),
          "actor_id" =>
            Zoi.union([
              Zoi.string() |> Zoi.min(1),
              Zoi.null()
            ])
            |> Zoi.optional(),
          "context" =>
            Zoi.map(
              %{
                "channel_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
                "team_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
                "enterprise_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional()
              },
              strict: true
            )
            |> Zoi.optional()
        },
        strict: true
      )
end
