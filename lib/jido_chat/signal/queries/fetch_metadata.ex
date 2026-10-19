defmodule Jido.Chat.Signal.FetchMetadata do
  @moduledoc "Typed query for fetch_metadata. Unsupported request fields are rejected."
  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :query,
    type: "jido.chat.query.fetch_metadata",
    dataschema: "urn:jido:chat:schema:query_fetch_metadata:3",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "client_id" => Jido.Chat.Signal.Schemas.id(),
          "request_id" => Jido.Chat.Signal.Schemas.id(),
          "room_id" => Jido.Chat.Signal.Schemas.id()
        },
        unrecognized_keys: :error
      )
end
