defmodule Jido.Chat.Signal.ReactionRemoved do
  @moduledoc """
  Typed fact definition for `jido.chat.reaction.removed`.

  Data uses the protocol version 1 string-key schema. The client-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :fact,
    type: "jido.chat.reaction.removed",
    dataschema: "urn:jido:chat:schema:reaction_removed:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "item_id" => Zoi.string() |> Zoi.min(1),
          "delivery_id" => Zoi.string() |> Zoi.min(1),
          "room_id" => Zoi.string() |> Zoi.min(1),
          "message_id" => Zoi.string() |> Zoi.min(1),
          "actor_id" => Zoi.string() |> Zoi.min(1),
          "reaction" =>
            Zoi.union([
              Zoi.string() |> Zoi.min(1),
              Zoi.null()
            ]),
          "thread_id" =>
            Zoi.union([
              Zoi.string() |> Zoi.min(1),
              Zoi.null()
            ])
            |> Zoi.optional()
        },
        unrecognized_keys: :error
      )
end
