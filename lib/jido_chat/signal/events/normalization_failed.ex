defmodule Jido.Chat.Signal.NormalizationFailed do
  @moduledoc """
  Typed fact definition for `jido.chat.normalization.failed`.

  Data uses the protocol version 1 string-key schema. The client-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Signal,
    type: "jido.chat.normalization.failed",
    dataschema: "urn:jido:chat:schema:normalization_failed:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Jido.Joi.map(
        %{
          "item_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "delivery_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "room_id" =>
            Jido.Joi.union([
              Jido.Joi.string() |> Jido.Joi.min(1),
              Jido.Joi.literal(nil)
            ])
            |> Jido.Joi.optional(),
          "code" => Jido.Joi.enum(["invalid_item", "unsupported_item", "invalid_context", "unsafe_data"]),
          "item_index" => Jido.Joi.integer() |> Jido.Joi.min(0),
          "provider_kind" => Jido.Joi.string() |> Jido.Joi.optional()
        },
        unrecognized_keys: :error
      )
end
