defmodule Jido.Chat.Signal.GetThreadParticipants do
  @moduledoc "Typed query for get_thread_participants. Unsupported request fields are rejected."
  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :query,
    type: "jido.chat.query.get_thread_participants",
    dataschema: "urn:jido:chat:schema:query_get_thread_participants:3",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "client_id" => Jido.Chat.Signal.Schemas.id(),
          "request_id" => Jido.Chat.Signal.Schemas.id(),
          "room_id" => Jido.Chat.Signal.Schemas.id(),
          "thread_id" => Jido.Chat.Signal.Schemas.id()
        },
        unrecognized_keys: :error
      )
end
