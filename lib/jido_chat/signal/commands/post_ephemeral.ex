defmodule Jido.Chat.Signal.PostEphemeral do
  @moduledoc "Typed command for post_ephemeral. Unsupported request fields are rejected."
  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :command,
    type: "jido.chat.command.post_ephemeral",
    dataschema: "urn:jido:chat:schema:command_post_ephemeral:3",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "client_id" => Jido.Chat.Signal.Schemas.id(),
          "request_id" => Jido.Chat.Signal.Schemas.id(),
          "room_id" => Jido.Chat.Signal.Schemas.id(),
          "user_id" => Jido.Chat.Signal.Schemas.id(),
          "text" => Jido.Chat.Signal.Schemas.id(),
          "thread_id" => Jido.Chat.Signal.Schemas.id() |> Zoi.optional(),
          "format" => Zoi.enum(["plain", "markdown", "html"]) |> Zoi.optional()
        },
        unrecognized_keys: :error
      )
end
