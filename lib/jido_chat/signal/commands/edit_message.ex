defmodule Jido.Chat.Signal.EditMessage do
  @moduledoc "Typed command for edit_message. Unsupported request fields are rejected."
  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :command,
    type: "jido.chat.command.edit_message",
    dataschema: "urn:jido:chat:schema:command_edit_message:3",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "client_id" => Jido.Chat.Signal.Schemas.id(),
          "request_id" => Jido.Chat.Signal.Schemas.id(),
          "room_id" => Jido.Chat.Signal.Schemas.id(),
          "message_id" => Jido.Chat.Signal.Schemas.id(),
          "text" => Jido.Chat.Signal.Schemas.id(),
          "format" => Zoi.enum(["plain", "markdown", "html"]) |> Zoi.optional(),
          "keyboard" => Jido.Chat.Signal.Schemas.keyboard() |> Zoi.optional()
        },
        unrecognized_keys: :error
      )
end
