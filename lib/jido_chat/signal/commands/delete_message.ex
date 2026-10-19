defmodule Jido.Chat.Signal.DeleteMessage do
  @moduledoc "Typed command for delete_message. Unsupported request fields are rejected."
  use Jido.Signal,
    type: "jido.chat.command.delete_message",
    dataschema: "urn:jido:chat:schema:command_delete_message:3",
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
