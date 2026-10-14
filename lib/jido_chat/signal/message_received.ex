defmodule Jido.Chat.Signal.MessageReceived do
  @moduledoc """
  Typed fact definition for `jido.chat.message.received`.

  Data uses the protocol version 1 string-key schema. The binding-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :fact,
    type: "jido.chat.message.received",
    dataschema: "urn:jido:chat:schema:message_received:1",
    default_source: "urn:jido:chat:binding:YmluZGluZy9hbHBoYQ",
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
              strict: true
            ),
          "text" => Zoi.string(),
          "thread_id" =>
            Zoi.union([
              Zoi.string() |> Zoi.min(1),
              Zoi.null()
            ])
            |> Zoi.optional(),
          "reply_to_id" =>
            Zoi.union([
              Zoi.string() |> Zoi.min(1),
              Zoi.null()
            ])
            |> Zoi.optional(),
          "media" =>
            Zoi.array(
              Zoi.map(
                %{
                  "kind" => Zoi.enum(["image", "audio", "video", "file"]),
                  "resource_ref" =>
                    Zoi.map(
                      %{
                        "id" => Zoi.string() |> Zoi.min(1),
                        "scope" => Zoi.enum(["call"]),
                        "binding_id" => Zoi.string() |> Zoi.min(1),
                        "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                      },
                      strict: true
                    ),
                  "name" => Zoi.string() |> Zoi.optional(),
                  "media_type" => Zoi.string() |> Zoi.optional(),
                  "caption" => Zoi.string() |> Zoi.optional()
                },
                strict: true
              )
            )
            |> Zoi.optional(),
          "mentions" => Zoi.array(Zoi.string() |> Zoi.min(1)) |> Zoi.optional(),
          "mentioned" => Zoi.boolean() |> Zoi.optional(),
          "timestamp" => Zoi.string() |> Zoi.optional(),
          "conversation_kind" => Zoi.enum(["direct", "group", "channel", "thread", "unknown"]) |> Zoi.optional(),
          "conversation_name" => Zoi.string() |> Zoi.optional(),
          "mention_details" =>
            Zoi.array(
              Zoi.map(
                %{
                  "id" => Zoi.string() |> Zoi.min(1),
                  "username" => Zoi.string() |> Zoi.optional(),
                  "offset" => Zoi.integer() |> Zoi.gte(0) |> Zoi.optional(),
                  "length" => Zoi.integer() |> Zoi.gte(0) |> Zoi.optional()
                },
                strict: true
              )
            )
            |> Zoi.optional(),
          "reply_context" =>
            Zoi.map(
              %{
                "id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
                "message_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
                "text" => Zoi.string() |> Zoi.optional(),
                "sender" =>
                  Zoi.map(
                    %{
                      "id" => Zoi.string() |> Zoi.min(1),
                      "username" => Zoi.string() |> Zoi.optional(),
                      "display_name" => Zoi.string() |> Zoi.optional(),
                      "is_bot" => Zoi.boolean() |> Zoi.optional(),
                      "is_self" => Zoi.boolean() |> Zoi.optional()
                    },
                    strict: true
                  )
                  |> Zoi.optional()
              },
              strict: true
            )
            |> Zoi.optional()
        },
        strict: true
      )
end
