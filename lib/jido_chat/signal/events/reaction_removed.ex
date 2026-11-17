defmodule Jido.Chat.Signal.ReactionRemoved do
  @moduledoc """
  Typed fact definition for `jido.chat.reaction.removed`.

  Data uses the protocol version 1 string-key schema. The client-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Signal,
    type: "jido.chat.reaction.removed",
    dataschema: "urn:jido:chat:schema:reaction_removed:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Jido.Joi.map(
        %{
          "item_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "delivery_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "room_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "message_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "actor_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "reaction" =>
            Jido.Joi.union([
              Jido.Joi.string() |> Jido.Joi.min(1),
              Jido.Joi.literal(nil)
            ]),
          "thread_id" =>
            Jido.Joi.union([
              Jido.Joi.string() |> Jido.Joi.min(1),
              Jido.Joi.literal(nil)
            ])
            |> Jido.Joi.optional()
        },
        unrecognized_keys: :error
      )
end
