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
      Zoi.map(
        %{
          "client_id" => Zoi.string() |> Zoi.min(1),
          "request_id" => Zoi.string() |> Zoi.min(1),
          "room_id" => Zoi.string() |> Zoi.min(1),
          "source" => Jido.Chat.Signal.Schemas.file_source(),
          "caption" => Zoi.string() |> Zoi.optional(),
          "media_kind" => Zoi.enum(["file", "image"]) |> Zoi.optional(),
          "thread_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
          "reply_to_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
          "format" => Zoi.enum(["plain", "markdown", "html"]) |> Zoi.optional(),
          "keyboard" => Jido.Chat.Signal.Schemas.keyboard() |> Zoi.optional()
        },
        unrecognized_keys: :error
      )
end
