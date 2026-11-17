defmodule Jido.Chat.Signal.StreamText do
  @moduledoc """
  Requests incremental text delivery. The source Enumerable is private Action
  context (`options[:stream]`), never Signal data. The adapter selects delivery.
  """
  use Jido.Signal,
    type: "jido.chat.command.stream_text",
    dataschema: "urn:jido:chat:schema:command_stream_text:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Jido.Chat.Signal.Schemas.object(%{
        "client_id" => Jido.Chat.Signal.Schemas.id(),
        "request_id" => Jido.Chat.Signal.Schemas.id(),
        "room_id" => Jido.Chat.Signal.Schemas.id(),
        "thread_id" => Jido.Chat.Signal.Schemas.id() |> Jido.Joi.optional(),
        "reply_to_id" => Jido.Chat.Signal.Schemas.id() |> Jido.Joi.optional(),
        "format" => Jido.Joi.enum(["plain", "markdown", "html"]) |> Jido.Joi.optional(),
        "keyboard" => Jido.Chat.Signal.Schemas.keyboard() |> Jido.Joi.optional(),
        "update_interval_ms" => Jido.Joi.integer() |> Jido.Joi.min(0) |> Jido.Joi.optional()
      })
end
