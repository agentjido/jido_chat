defmodule Jido.Chat.Signal.OpenModal do
  @moduledoc "Typed command for open_modal. Unsupported request fields are rejected."
  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :command,
    type: "jido.chat.command.open_modal",
    dataschema: "urn:jido:chat:schema:command_open_modal:3",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "client_id" => Jido.Chat.Signal.Schemas.id(),
          "request_id" => Jido.Chat.Signal.Schemas.id(),
          "room_id" => Jido.Chat.Signal.Schemas.id(),
          "modal" => Zoi.map()
        },
        unrecognized_keys: :error
      )
end
