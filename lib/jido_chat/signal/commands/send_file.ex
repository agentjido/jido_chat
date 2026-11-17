defmodule Jido.Chat.Signal.SendFile do
  @moduledoc """
  Typed command definition for `jido.chat.command.send_file`.

  Data uses the protocol version 3 string-key schema. Request may omit subject. If present, it must equal conversation_subject(client_id, room_id). A room result uses that conversation subject.
  """

  use Jido.Signal,
    type: "jido.chat.command.send_file",
    dataschema: "urn:jido:chat:schema:command_send_file:3",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Jido.Joi.map(
        %{
          "client_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "request_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "room_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "source" => Jido.Chat.Signal.Schemas.file_source(),
          "caption" => Jido.Joi.string() |> Jido.Joi.optional(),
          "media_kind" => Jido.Joi.enum(["file", "image"]) |> Jido.Joi.optional(),
          "thread_id" => Jido.Joi.string() |> Jido.Joi.min(1) |> Jido.Joi.optional(),
          "reply_to_id" => Jido.Joi.string() |> Jido.Joi.min(1) |> Jido.Joi.optional(),
          "format" => Jido.Joi.enum(["plain", "markdown", "html"]) |> Jido.Joi.optional(),
          "keyboard" => Jido.Chat.Signal.Schemas.keyboard() |> Jido.Joi.optional()
        },
        unrecognized_keys: :error
      )
end
