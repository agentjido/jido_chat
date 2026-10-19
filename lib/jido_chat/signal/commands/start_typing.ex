defmodule Jido.Chat.Signal.StartTyping do
  @moduledoc "Typed command for start_typing. Unsupported request fields are rejected."
  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :command,
    type: "jido.chat.command.start_typing",
    dataschema: "urn:jido:chat:schema:command_start_typing:3",
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
