defmodule Jido.Chat.Signal.GetUser do
  @moduledoc "Typed query for get_user. Unsupported request fields are rejected."
  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :query,
    type: "jido.chat.query.get_user",
    dataschema: "urn:jido:chat:schema:query_get_user:3",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "client_id" => Jido.Chat.Signal.Schemas.id(),
          "request_id" => Jido.Chat.Signal.Schemas.id(),
          "user_id" => Jido.Chat.Signal.Schemas.id()
        },
        unrecognized_keys: :error
      )
end
