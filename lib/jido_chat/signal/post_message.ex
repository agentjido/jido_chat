defmodule Jido.Chat.Signal.PostMessage do
  @moduledoc """
  Typed command definition for `jido.chat.command.post_message`.

  Data uses the protocol version 1 string-key schema. Request may omit subject. If present, it must equal conversation_subject(binding_id, room_id). A room result uses that conversation subject.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :command,
    type: "jido.chat.command.post_message",
    dataschema: "urn:jido:chat:schema:command_post_message:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "request_id" => Zoi.string() |> Zoi.min(1),
          "room_id" => Zoi.string() |> Zoi.min(1),
          "content" =>
            Zoi.union([
              Zoi.map(
                %{
                  "kind" => Zoi.enum(["text", "markdown"]),
                  "text" => Zoi.string()
                },
                strict: true
              ),
              Zoi.map(
                %{
                  "kind" => Zoi.enum(["card", "stream", "media"]),
                  "resource_ref" =>
                    Zoi.map(
                      %{
                        "id" => Zoi.string() |> Zoi.min(1),
                        "scope" => Zoi.enum(["call"]),
                        "binding_id" => Zoi.string() |> Zoi.min(1),
                        "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                      },
                      strict: true
                    ),
                  "fallback_text" => Zoi.string() |> Zoi.optional(),
                  "caption" => Zoi.string() |> Zoi.optional()
                },
                strict: true
              )
            ]),
          "thread_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
          "reply_to_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
          "format" => Zoi.enum(["plain", "markdown", "html"]) |> Zoi.optional()
        },
        strict: true
      )
end
