defmodule Jido.Chat.Signal.SendMessage do
  @moduledoc """
  Typed command definition for `jido.chat.command.send_message`.

  Data uses the protocol version 2 string-key schema. Request may omit subject. If present, it must equal conversation_subject(client_id, room_id). A room result uses that conversation subject.
  """

  use Jido.Signal,
    type: "jido.chat.command.send_message",
    dataschema: "urn:jido:chat:schema:command_send_message:2",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Jido.Joi.map(
        %{
          "client_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "request_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "room_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "text" => Jido.Joi.string(),
          "thread_id" => Jido.Joi.string() |> Jido.Joi.min(1) |> Jido.Joi.optional(),
          "reply_to_id" => Jido.Joi.string() |> Jido.Joi.min(1) |> Jido.Joi.optional(),
          "format" => Jido.Joi.enum(["plain", "markdown", "html"]) |> Jido.Joi.optional(),
          "keyboard" => Jido.Chat.Signal.Schemas.keyboard() |> Jido.Joi.optional()
        },
        unrecognized_keys: :error
      )
end
