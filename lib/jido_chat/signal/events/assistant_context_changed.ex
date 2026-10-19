defmodule Jido.Chat.Signal.AssistantContextChanged do
  @moduledoc """
  Typed fact definition for `jido.chat.assistant.context_changed`.

  Data uses the protocol version 1 string-key schema. The client-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :fact,
    type: "jido.chat.assistant.context_changed",
    dataschema: "urn:jido:chat:schema:assistant_context_changed:1",
    default_source: "urn:jido:chat:producer:local",
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
              unrecognized_keys: :error
            )
        },
        unrecognized_keys: :error
      )
end
