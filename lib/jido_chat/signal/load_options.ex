defmodule Jido.Chat.Signal.LoadOptions do
  @moduledoc """
  Typed query definition for `jido.chat.query.load_options`.

  Data uses the protocol version 1 string-key schema. Use the binding-scoped room subject only when an interaction room is known; absence is permitted for an interaction with no room.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :query,
    type: "jido.chat.query.load_options",
    dataschema: "urn:jido:chat:schema:query_load_options:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "request_id" => Zoi.string() |> Zoi.min(1),
          "interaction_id" => Zoi.string() |> Zoi.min(1),
          "query" => Zoi.string(),
          "thread_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
          "reply_to_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
          "format" => Zoi.enum(["plain", "markdown", "html"]) |> Zoi.optional(),
          "action_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
          "room_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
          "view_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
          "user_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
          "limit" => Zoi.integer() |> Zoi.gte(1) |> Zoi.optional()
        },
        strict: true
      )
end
