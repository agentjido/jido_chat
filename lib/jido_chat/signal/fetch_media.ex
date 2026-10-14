defmodule Jido.Chat.Signal.FetchMedia do
  @moduledoc """
  Typed query definition for `jido.chat.query.fetch_media`.

  Data uses the protocol version 1 string-key schema. No room subject is required; subject absence is permitted for the scoped media resource and its result.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :query,
    type: "jido.chat.query.fetch_media",
    dataschema: "urn:jido:chat:schema:query_fetch_media:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "request_id" => Zoi.string() |> Zoi.min(1),
          "media_ref" =>
            Zoi.map(
              %{
                "id" => Zoi.string() |> Zoi.min(1),
                "scope" => Zoi.enum(["call"]),
                "binding_id" => Zoi.string() |> Zoi.min(1),
                "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
              },
              strict: true
            ),
          "thread_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
          "reply_to_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
          "format" => Zoi.enum(["plain", "markdown", "html"]) |> Zoi.optional()
        },
        strict: true
      )
end
