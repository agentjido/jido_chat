defmodule Jido.Chat.Signal.RemoveReaction do
  @moduledoc "Typed command for remove_reaction. Unsupported request fields are rejected."
  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :command,
    type: "jido.chat.command.remove_reaction",
    dataschema: "urn:jido:chat:schema:command_remove_reaction:3",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "client_id" => Jido.Chat.Signal.Schemas.id(),
          "request_id" => Jido.Chat.Signal.Schemas.id(),
          "room_id" => Jido.Chat.Signal.Schemas.id(),
          "message_id" => Jido.Chat.Signal.Schemas.id(),
          "reaction" => Jido.Chat.Signal.Schemas.id()
        },
        unrecognized_keys: :error
      )
end
