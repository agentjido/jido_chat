defmodule Jido.Chat.Telegram.DeleteWebhook do
  @moduledoc "Runs one Telegram delete_webhook request with an explicit Client."
  use Jido.ChatAction,
    name: "telegram_delete_webhook",
    signal: Jido.Chat.Telegram.Signal.DeleteWebhook,
    result_schema: Jido.Chat.Signal.Schemas.result(:acknowledgement)

  @impl Jido.ChatAction
  def invoke(client, signal, opts), do: Jido.Chat.Telegram.Operations.invoke(:delete_webhook, client, signal, opts)
end
