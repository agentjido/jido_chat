defmodule Jido.Chat.Discord.Signal.StartMessageThread do
  @moduledoc "Typed request to start a thread on an existing Discord message."
  use Jido.Signal,
    type: "jido.chat.discord.command.start_message_thread",
    dataschema: "urn:jido:chat:discord:start_message_thread:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "client_id" => Jido.Chat.Signal.Schemas.id(),
          "request_id" => Jido.Chat.Signal.Schemas.id(),
          "room_id" => Jido.Chat.Signal.Schemas.id(),
          "message_id" => Jido.Chat.Signal.Schemas.id(),
          "name" => Jido.Chat.Signal.Schemas.id()
        },
        unrecognized_keys: :error
      )
end
