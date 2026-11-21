defmodule Jido.Chat.Telegram.Signal.SetWebhook do
  @moduledoc "Typed Telegram set_webhook request."
  alias Jido.Chat.Telegram.Signal.Schemas

  use Jido.Signal,
    type: "jido.chat.telegram.command.set_webhook",
    dataschema: "urn:jido:chat:telegram:set_webhook:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Schemas.request(%{
        "url" => Schemas.id(),
        "allowed_updates" => Zoi.array(Zoi.string()) |> Zoi.optional(),
        "max_connections" => Zoi.integer() |> Zoi.min(1) |> Zoi.max(100) |> Zoi.optional(),
        "drop_pending_updates" => Zoi.boolean() |> Zoi.optional()
      })
end
