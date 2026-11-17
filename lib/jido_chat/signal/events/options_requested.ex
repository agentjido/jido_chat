defmodule Jido.Chat.Signal.OptionsRequested do
  @moduledoc """
  Typed fact definition for `jido.chat.options.requested`.

  Data uses the protocol version 1 string-key schema. The client-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Signal,
    type: "jido.chat.options.requested",
    dataschema: "urn:jido:chat:schema:options_requested:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Jido.Joi.map(
        %{
          "item_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "delivery_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "room_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "interaction_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "action_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "query" => Jido.Joi.string(),
          "actor_id" =>
            Jido.Joi.union([
              Jido.Joi.string() |> Jido.Joi.min(1),
              Jido.Joi.literal(nil)
            ])
            |> Jido.Joi.optional(),
          "view_id" =>
            Jido.Joi.union([
              Jido.Joi.string() |> Jido.Joi.min(1),
              Jido.Joi.literal(nil)
            ])
            |> Jido.Joi.optional(),
          "limit" => Jido.Joi.integer() |> Jido.Joi.min(1) |> Jido.Joi.optional()
        },
        unrecognized_keys: :error
      )
end
