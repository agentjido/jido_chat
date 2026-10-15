defmodule Jido.Chat.Signal.MessageUpdated do
  @moduledoc """
  Typed fact definition for `jido.chat.message.updated`.

  Data uses the protocol version 1 string-key schema. The binding-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :fact,
    type: "jido.chat.message.updated",
    dataschema: "urn:jido:chat:schema:message_updated:1",
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
                      unrecognized_keys: :error
                    ),
                  "name" => Zoi.string() |> Zoi.optional(),
                  "media_type" => Zoi.string() |> Zoi.optional(),
                  "caption" => Zoi.string() |> Zoi.optional()
                },
                unrecognized_keys: :error
              )
            )
            |> Zoi.optional(),
          "timestamp" => Zoi.string() |> Zoi.optional()
        },
        unrecognized_keys: :error
      )
end
