defmodule Jido.Chat.Signal.StreamText do
  @moduledoc """
  Requests incremental text delivery. The source Enumerable is private Action
  context (`options[:stream]`), never Signal data. The adapter selects delivery.
  """
  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :command,
    type: "jido.chat.command.stream_text",
    dataschema: "urn:jido:chat:schema:command_stream_text:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Jido.Chat.Signal.Schemas.object(%{
        "client_id" => Jido.Chat.Signal.Schemas.id(),
        "request_id" => Jido.Chat.Signal.Schemas.id(),
        "room_id" => Jido.Chat.Signal.Schemas.id(),
        "thread_id" => Jido.Chat.Signal.Schemas.id() |> Zoi.optional(),
        "reply_to_id" => Jido.Chat.Signal.Schemas.id() |> Zoi.optional(),
        "format" => Zoi.enum(["plain", "markdown", "html"]) |> Zoi.optional(),
        "keyboard" => Jido.Chat.Signal.Schemas.keyboard() |> Zoi.optional(),
        "update_interval_ms" => Zoi.integer() |> Zoi.min(0) |> Zoi.optional()
      })
end
