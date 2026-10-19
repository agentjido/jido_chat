defmodule Jido.Chat.Signal.SendMessage do
  @moduledoc """
  Typed command definition for `jido.chat.command.send_message`.

  Data uses the protocol version 2 string-key schema. Request may omit subject. If present, it must equal conversation_subject(client_id, room_id). A room result uses that conversation subject.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :command,
    type: "jido.chat.command.send_message",
    dataschema: "urn:jido:chat:schema:command_send_message:2",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "client_id" => Zoi.string() |> Zoi.min(1),
          "request_id" => Zoi.string() |> Zoi.min(1),
          "room_id" => Zoi.string() |> Zoi.min(1),
          "text" => Zoi.string(),
          "thread_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
          "reply_to_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
          "format" => Zoi.enum(["plain", "markdown", "html"]) |> Zoi.optional(),
          "keyboard" => Jido.Chat.Signal.Schemas.keyboard() |> Zoi.optional()
        },
        unrecognized_keys: :error
      )
end
