defmodule Jido.Chat.Signal.CreateThread do
  @moduledoc "Typed command for create_thread. Unsupported request fields are rejected."
  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :command,
    type: "jido.chat.command.create_thread",
    dataschema: "urn:jido:chat:schema:command_create_thread:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "client_id" => Jido.Chat.Signal.Schemas.id(),
          "request_id" => Jido.Chat.Signal.Schemas.id(),
          "room_id" => Jido.Chat.Signal.Schemas.id(),
          "name" => Jido.Chat.Signal.Schemas.id()
        },
        unrecognized_keys: :error
      )
end
