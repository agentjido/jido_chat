defmodule Jido.Chat.Signal.OpenDm do
  @moduledoc "Typed command for open_dm. Unsupported request fields are rejected."
  use Jido.Signal,
    type: "jido.chat.command.open_dm",
    dataschema: "urn:jido:chat:schema:command_open_dm:3",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "client_id" => Jido.Chat.Signal.Schemas.id(),
          "request_id" => Jido.Chat.Signal.Schemas.id(),
          "user_id" => Jido.Chat.Signal.Schemas.id()
        },
        unrecognized_keys: :error
      )
end
