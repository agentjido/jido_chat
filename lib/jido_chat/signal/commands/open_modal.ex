defmodule Jido.Chat.Signal.OpenModal do
  @moduledoc "Typed command for open_modal. Unsupported request fields are rejected."
  use Jido.Signal,
    type: "jido.chat.command.open_modal",
    dataschema: "urn:jido:chat:schema:command_open_modal:4",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "client_id" => Jido.Chat.Signal.Schemas.id(),
          "request_id" => Jido.Chat.Signal.Schemas.id(),
          "room_id" => Jido.Chat.Signal.Schemas.id(),
          "modal" => Jido.Chat.Signal.Schemas.modal()
        },
        unrecognized_keys: :error
      )
end
