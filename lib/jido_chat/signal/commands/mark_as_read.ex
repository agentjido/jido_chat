defmodule Jido.Chat.Signal.MarkAsRead do
  @moduledoc "Typed command for mark_as_read. Unsupported request fields are rejected."
  use Jido.Signal,
    type: "jido.chat.command.mark_as_read",
    dataschema: "urn:jido:chat:schema:command_mark_as_read:3",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "client_id" => Jido.Chat.Signal.Schemas.id(),
          "request_id" => Jido.Chat.Signal.Schemas.id(),
          "room_id" => Jido.Chat.Signal.Schemas.id(),
          "message_id" => Jido.Chat.Signal.Schemas.id()
        },
        unrecognized_keys: :error
      )
end
