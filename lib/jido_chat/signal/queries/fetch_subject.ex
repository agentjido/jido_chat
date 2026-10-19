defmodule Jido.Chat.Signal.FetchSubject do
  @moduledoc "Typed query for fetch_subject. Unsupported request fields are rejected."
  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :query,
    type: "jido.chat.query.fetch_subject",
    dataschema: "urn:jido:chat:schema:query_fetch_subject:3",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "client_id" => Jido.Chat.Signal.Schemas.id(),
          "request_id" => Jido.Chat.Signal.Schemas.id(),
          "room_id" => Jido.Chat.Signal.Schemas.id(),
          "thread_id" => Jido.Chat.Signal.Schemas.id() |> Zoi.optional()
        },
        unrecognized_keys: :error
      )
end
