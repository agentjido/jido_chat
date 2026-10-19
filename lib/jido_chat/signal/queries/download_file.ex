defmodule Jido.Chat.Signal.DownloadFile do
  @moduledoc "Typed query for download_file. Unsupported request fields are rejected."
  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :query,
    type: "jido.chat.query.download_file",
    dataschema: "urn:jido:chat:schema:query_download_file:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "client_id" => Jido.Chat.Signal.Schemas.id(),
          "request_id" => Jido.Chat.Signal.Schemas.id(),
          "resource_ref" => Jido.Chat.Signal.Schemas.reference()
        },
        unrecognized_keys: :error
      )
end
