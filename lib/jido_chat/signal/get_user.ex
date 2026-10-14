defmodule Jido.Chat.Signal.GetUser do
  @moduledoc """
  Typed query definition for `jido.chat.query.get_user`.

  Data uses the protocol version 1 string-key schema. No room subject is required; subject absence is permitted for user lookup and its result.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :query,
    type: "jido.chat.query.get_user",
    dataschema: "urn:jido:chat:schema:query_get_user:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "request_id" => Zoi.string() |> Zoi.min(1),
          "user_id" => Zoi.string() |> Zoi.min(1),
          "thread_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
          "reply_to_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
          "format" => Zoi.enum(["plain", "markdown", "html"]) |> Zoi.optional()
        },
        unrecognized_keys: :error
      )
end
