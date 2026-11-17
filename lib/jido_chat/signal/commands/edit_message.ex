defmodule Jido.Chat.Signal.EditMessage do
  @moduledoc "Typed command for edit_message. Unsupported request fields are rejected."
  use Jido.Signal,
    type: "jido.chat.command.edit_message",
    dataschema: "urn:jido:chat:schema:command_edit_message:3",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Jido.Joi.map(
        %{
          "client_id" => Jido.Chat.Signal.Schemas.id(),
          "request_id" => Jido.Chat.Signal.Schemas.id(),
          "room_id" => Jido.Chat.Signal.Schemas.id(),
          "message_id" => Jido.Chat.Signal.Schemas.id(),
          "text" => Jido.Chat.Signal.Schemas.id(),
          "format" => Jido.Joi.enum(["plain", "markdown", "html"]) |> Jido.Joi.optional(),
          "keyboard" => Jido.Chat.Signal.Schemas.keyboard() |> Jido.Joi.optional()
        },
        unrecognized_keys: :error
      )
end
