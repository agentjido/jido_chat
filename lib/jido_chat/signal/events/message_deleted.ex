defmodule Jido.Chat.Signal.MessageDeleted do
  @moduledoc """
  Typed fact definition for `jido.chat.message.deleted`.

  Data uses the protocol version 1 string-key schema. The client-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Signal,
    type: "jido.chat.message.deleted",
    dataschema: "urn:jido:chat:schema:message_deleted:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Jido.Joi.map(
        %{
          "item_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "delivery_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "room_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "message_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "actor_id" =>
            Jido.Joi.union([
              Jido.Joi.string() |> Jido.Joi.min(1),
              Jido.Joi.literal(nil)
            ])
            |> Jido.Joi.optional(),
          "thread_id" =>
            Jido.Joi.union([
              Jido.Joi.string() |> Jido.Joi.min(1),
              Jido.Joi.literal(nil)
            ])
            |> Jido.Joi.optional(),
          "timestamp" => Jido.Joi.string() |> Jido.Joi.optional()
        },
        unrecognized_keys: :error
      )
end
