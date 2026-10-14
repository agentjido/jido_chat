defmodule Jido.Chat.Signal.OpenDm do
  @moduledoc """
  Typed command definition for `jido.chat.command.open_dm`.

  Data uses the protocol version 1 string-key schema. Request has no conversation subject. Success uses conversation_subject(binding_id, result.id) for the opened DM; failure may omit subject.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :command,
    type: "jido.chat.command.open_dm",
    dataschema: "urn:jido:chat:schema:command_open_dm:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "request_id" => Zoi.string() |> Zoi.min(1),
          "user_id" => Zoi.string() |> Zoi.min(1),
          "thread_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
          "reply_to_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
          "format" => Zoi.enum(["plain", "markdown", "html"]) |> Zoi.optional()
        },
        strict: true
      )
end
