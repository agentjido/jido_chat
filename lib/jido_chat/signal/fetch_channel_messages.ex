defmodule Jido.Chat.Signal.FetchChannelMessages do
  @moduledoc """
  Typed query definition for `jido.chat.query.fetch_channel_messages`.

  Data uses the protocol version 1 string-key schema. Request may omit subject. If present, it must equal conversation_subject(binding_id, room_id). A room result uses that conversation subject.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :query,
    type: "jido.chat.query.fetch_channel_messages",
    dataschema: "urn:jido:chat:schema:query_fetch_channel_messages:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "request_id" => Zoi.string() |> Zoi.min(1),
          "room_id" => Zoi.string() |> Zoi.min(1),
          "thread_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
          "reply_to_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
          "format" => Zoi.enum(["plain", "markdown", "html"]) |> Zoi.optional(),
          "cursor" =>
            Zoi.union([
              Zoi.string() |> Zoi.min(1),
              Zoi.null()
            ])
            |> Zoi.optional(),
          "limit" => Zoi.integer() |> Zoi.gte(1) |> Zoi.optional(),
          "direction" => Zoi.enum(["forward", "backward"]) |> Zoi.optional()
        },
        strict: true
      )
end
