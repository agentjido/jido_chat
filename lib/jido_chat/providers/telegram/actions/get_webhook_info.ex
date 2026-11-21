defmodule Jido.Chat.Telegram.GetWebhookInfo do
  @moduledoc "Runs one Telegram get_webhook_info request with an explicit Client."
  alias Jido.Chat.Telegram.Signal.Schemas

  use Jido.ChatAction,
    name: "telegram_get_webhook_info",
    signal: Jido.Chat.Telegram.Signal.GetWebhookInfo,
    result_schema: Schemas.webhook_result()

  @impl Jido.ChatAction
  def invoke(client, signal, opts), do: Jido.Chat.Telegram.Operations.invoke(:get_webhook_info, client, signal, opts)
end
