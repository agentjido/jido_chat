defmodule Jido.Chat.Telegram.Signal.GetWebhookInfo do
  @moduledoc "Typed Telegram get_webhook_info request."
  alias Jido.Chat.Telegram.Signal.Schemas

  use Jido.Signal,
    type: "jido.chat.telegram.query.get_webhook_info",
    dataschema: "urn:jido:chat:telegram:get_webhook_info:1",
    default_source: "urn:jido:chat:producer:local",
    schema: Schemas.request(%{})
end
