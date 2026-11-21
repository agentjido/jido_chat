defmodule Jido.Chat.Telegram.SetWebhook do
  @moduledoc "Runs one Telegram set_webhook request with an explicit Client."
  use Jido.ChatAction,
    name: "telegram_set_webhook",
    signal: Jido.Chat.Telegram.Signal.SetWebhook,
    result_schema: Jido.Chat.Signal.Schemas.result(:acknowledgement)

  @impl Jido.ChatAction
  def invoke(client, signal, opts), do: Jido.Chat.Telegram.Operations.invoke(:set_webhook, client, signal, opts)
end
