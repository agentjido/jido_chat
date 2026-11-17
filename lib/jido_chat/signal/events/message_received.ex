defmodule Jido.Chat.Signal.MessageReceived do
  @moduledoc """
  Typed fact definition for `jido.chat.message.received`.

  Data uses the protocol version 2 string-key schema. The client-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Signal,
    type: "jido.chat.message.received",
    dataschema: "urn:jido:chat:schema:message_received:2",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Jido.Joi.map(
        %{
          "item_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "delivery_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "room_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "message_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "sender" =>
            Jido.Joi.map(
              %{
                "id" => Jido.Joi.string() |> Jido.Joi.min(1),
                "username" => Jido.Joi.string() |> Jido.Joi.optional(),
                "display_name" => Jido.Joi.string() |> Jido.Joi.optional(),
                "is_bot" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                "is_self" => Jido.Joi.boolean() |> Jido.Joi.optional()
              },
              unrecognized_keys: :error
            ),
          "text" => Jido.Joi.string(),
          "thread_id" =>
            Jido.Joi.union([
              Jido.Joi.string() |> Jido.Joi.min(1),
              Jido.Joi.literal(nil)
            ])
            |> Jido.Joi.optional(),
          "reply_to_id" =>
            Jido.Joi.union([
              Jido.Joi.string() |> Jido.Joi.min(1),
              Jido.Joi.literal(nil)
            ])
            |> Jido.Joi.optional(),
          "media" => Jido.Joi.array(Jido.Chat.Signal.Schemas.media()) |> Jido.Joi.optional(),
          "mentions" => Jido.Joi.array(Jido.Joi.string() |> Jido.Joi.min(1)) |> Jido.Joi.optional(),
          "mentioned" => Jido.Joi.boolean() |> Jido.Joi.optional(),
          "timestamp" => Jido.Joi.string() |> Jido.Joi.optional(),
          "conversation_kind" =>
            Jido.Joi.enum(["direct", "group", "channel", "thread", "unknown"]) |> Jido.Joi.optional(),
          "conversation_name" => Jido.Joi.string() |> Jido.Joi.optional(),
          "mention_details" =>
            Jido.Joi.array(
              Jido.Joi.map(
                %{
                  "id" => Jido.Joi.string() |> Jido.Joi.min(1),
                  "username" => Jido.Joi.string() |> Jido.Joi.optional(),
                  "offset" => Jido.Joi.integer() |> Jido.Joi.min(0) |> Jido.Joi.optional(),
                  "length" => Jido.Joi.integer() |> Jido.Joi.min(0) |> Jido.Joi.optional()
                },
                unrecognized_keys: :error
              )
            )
            |> Jido.Joi.optional(),
          "reply_context" =>
            Jido.Joi.map(
              %{
                "id" => Jido.Joi.string() |> Jido.Joi.min(1) |> Jido.Joi.optional(),
                "message_id" => Jido.Joi.string() |> Jido.Joi.min(1) |> Jido.Joi.optional(),
                "text" => Jido.Joi.string() |> Jido.Joi.optional(),
                "sender" =>
                  Jido.Joi.map(
                    %{
                      "id" => Jido.Joi.string() |> Jido.Joi.min(1),
                      "username" => Jido.Joi.string() |> Jido.Joi.optional(),
                      "display_name" => Jido.Joi.string() |> Jido.Joi.optional(),
                      "is_bot" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                      "is_self" => Jido.Joi.boolean() |> Jido.Joi.optional()
                    },
                    unrecognized_keys: :error
                  )
                  |> Jido.Joi.optional()
              },
              unrecognized_keys: :error
            )
            |> Jido.Joi.optional()
        },
        unrecognized_keys: :error
      )
end
