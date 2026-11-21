defmodule Jido.Chat.Telegram.Signal.DeleteWebhook do
  @moduledoc "Typed Telegram delete_webhook request."
  alias Jido.Chat.Telegram.Signal.Schemas

  use Jido.Signal,
    type: "jido.chat.telegram.command.delete_webhook",
    dataschema: "urn:jido:chat:telegram:delete_webhook:1",
    default_source: "urn:jido:chat:producer:local",
    schema: Schemas.request(%{"drop_pending_updates" => Zoi.boolean() |> Zoi.optional()})
end
