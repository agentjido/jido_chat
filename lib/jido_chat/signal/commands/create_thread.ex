defmodule Jido.Chat.Signal.CreateThread do
  @moduledoc "Typed command for create_thread. Unsupported request fields are rejected."
  alias Jido.Chat.Signal.Schemas

  use Jido.Signal,
    type: "jido.chat.command.create_thread",
    dataschema: "urn:jido:chat:schema:command_create_thread:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Schemas.object(%{
        "client_id" => Schemas.id(),
        "request_id" => Schemas.id(),
        "room_id" => Schemas.id(),
        "name" => Schemas.id()
      })
end
