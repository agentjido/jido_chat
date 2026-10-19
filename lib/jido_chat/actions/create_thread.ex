defmodule Jido.Chat.CreateThread do
  @moduledoc "Creates a named chat thread. Agent routes defer provider execution until after commit."
  alias Jido.Chat.Signal.Schemas

  use Jido.ChatAction,
    name: "chat_create_thread",
    description: "Create a named chat thread",
    vsn: 1,
    input: [
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
    ],
    output: [
      type: "jido.chat.command.create_thread.completed",
      dataschema: "urn:jido:chat:schema:command_create_thread:1:completed",
      default_source: "urn:jido:chat:producer:local",
      schema:
        Schemas.completion(
          "jido.chat.command.create_thread",
          Schemas.result(:created_thread)
        )
    ]
end
