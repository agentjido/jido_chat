defmodule Jido.Chat.Signal.MessageUpdated do
  @moduledoc """
  Typed fact definition for `jido.chat.message.updated`.

  Data uses the protocol version 2 string-key schema. The client-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :fact,
    type: "jido.chat.message.updated",
    dataschema: "urn:jido:chat:schema:message_updated:2",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "item_id" => Zoi.string() |> Zoi.min(1),
          "delivery_id" => Zoi.string() |> Zoi.min(1),
          "room_id" => Zoi.string() |> Zoi.min(1),
          "message_id" => Zoi.string() |> Zoi.min(1),
          "sender" =>
            Zoi.map(
              %{
                "id" => Zoi.string() |> Zoi.min(1),
                "username" => Zoi.string() |> Zoi.optional(),
                "display_name" => Zoi.string() |> Zoi.optional(),
                "is_bot" => Zoi.boolean() |> Zoi.optional(),
                "is_self" => Zoi.boolean() |> Zoi.optional()
              },
              unrecognized_keys: :error
            )
            |> Zoi.optional(),
          "text" =>
            Zoi.union([
              Zoi.string(),
              Zoi.null()
            ]),
          "thread_id" =>
            Zoi.union([
              Zoi.string() |> Zoi.min(1),
              Zoi.null()
            ])
            |> Zoi.optional(),
          "media" => Zoi.array(Jido.Chat.Signal.Schemas.media()) |> Zoi.optional(),
          "timestamp" => Zoi.string() |> Zoi.optional()
        },
        unrecognized_keys: :error
      )
end
