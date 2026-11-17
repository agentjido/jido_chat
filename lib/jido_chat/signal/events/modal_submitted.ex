defmodule Jido.Chat.Signal.ModalSubmitted do
  @moduledoc """
  Typed fact definition for `jido.chat.modal.submitted`.

  Data uses the protocol version 1 string-key schema. The client-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Signal,
    type: "jido.chat.modal.submitted",
    dataschema: "urn:jido:chat:schema:modal_submitted:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Jido.Joi.map(
        %{
          "item_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "delivery_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "room_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "interaction_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "view_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "callback_id" =>
            Jido.Joi.union([
              Jido.Joi.string() |> Jido.Joi.min(1),
              Jido.Joi.literal(nil)
            ])
            |> Jido.Joi.optional(),
          "actor_id" =>
            Jido.Joi.union([
              Jido.Joi.string() |> Jido.Joi.min(1),
              Jido.Joi.literal(nil)
            ])
            |> Jido.Joi.optional(),
          "values" =>
            Jido.Joi.map(
              %{},
              unrecognized_keys:
                {:preserve,
                 {Jido.Joi.string(),
                  Jido.Joi.union([
                    Jido.Joi.string(),
                    Jido.Joi.array(Jido.Joi.string()),
                    Jido.Joi.boolean(),
                    Jido.Joi.number(),
                    Jido.Joi.literal(nil)
                  ])}}
            )
        },
        unrecognized_keys: :error
      )
end
