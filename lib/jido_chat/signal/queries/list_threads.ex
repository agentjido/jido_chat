defmodule Jido.Chat.Signal.ListThreads do
  @moduledoc "Typed query for list_threads. Unsupported request fields are rejected."
  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :query,
    type: "jido.chat.query.list_threads",
    dataschema: "urn:jido:chat:schema:query_list_threads:3",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "client_id" => Jido.Chat.Signal.Schemas.id(),
          "request_id" => Jido.Chat.Signal.Schemas.id(),
          "room_id" => Jido.Chat.Signal.Schemas.id(),
          "cursor" => Jido.Chat.Signal.Schemas.optional_id(),
          "limit" => Zoi.integer() |> Zoi.min(1) |> Zoi.optional(),
          "direction" => Zoi.enum(["forward", "backward"]) |> Zoi.optional()
        },
        unrecognized_keys: :error
      )
end
