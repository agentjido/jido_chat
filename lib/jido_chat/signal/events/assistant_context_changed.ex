defmodule Jido.Chat.Signal.AssistantContextChanged do
  @moduledoc """
  Typed fact definition for `jido.chat.assistant.context_changed`.

  Data uses the protocol version 1 string-key schema. The client-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Signal,
    type: "jido.chat.assistant.context_changed",
    dataschema: "urn:jido:chat:schema:assistant_context_changed:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Jido.Joi.map(
        %{
          "item_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "delivery_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "room_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "thread_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "actor_id" =>
            Jido.Joi.union([
              Jido.Joi.string() |> Jido.Joi.min(1),
              Jido.Joi.literal(nil)
            ])
            |> Jido.Joi.optional(),
          "context" =>
            Jido.Joi.map(
              %{
                "channel_id" => Jido.Joi.string() |> Jido.Joi.min(1) |> Jido.Joi.optional(),
                "team_id" => Jido.Joi.string() |> Jido.Joi.min(1) |> Jido.Joi.optional(),
                "enterprise_id" => Jido.Joi.string() |> Jido.Joi.min(1) |> Jido.Joi.optional()
              },
              unrecognized_keys: :error
            )
        },
        unrecognized_keys: :error
      )
end
