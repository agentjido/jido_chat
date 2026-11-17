defmodule Jido.Chat.Signal.PostEphemeral do
  @moduledoc "Typed command for post_ephemeral. Unsupported request fields are rejected."
  use Jido.Signal,
    type: "jido.chat.command.post_ephemeral",
    dataschema: "urn:jido:chat:schema:command_post_ephemeral:3",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Jido.Joi.map(
        %{
          "client_id" => Jido.Chat.Signal.Schemas.id(),
          "request_id" => Jido.Chat.Signal.Schemas.id(),
          "room_id" => Jido.Chat.Signal.Schemas.id(),
          "user_id" => Jido.Chat.Signal.Schemas.id(),
          "text" => Jido.Chat.Signal.Schemas.id(),
          "thread_id" => Jido.Chat.Signal.Schemas.id() |> Jido.Joi.optional(),
          "format" => Jido.Joi.enum(["plain", "markdown", "html"]) |> Jido.Joi.optional()
        },
        unrecognized_keys: :error
      )
end
