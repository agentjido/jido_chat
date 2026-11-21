defmodule Jido.Chat.Discord.SendRichMessage do
  @moduledoc "Send Discord embeds and components through an explicit Client."
  use Jido.ChatAction,
    name: "discord_send_rich_message",
    signal: Jido.Chat.Discord.Signal.SendRichMessage,
    result_schema: Jido.Chat.Signal.Schemas.result(:message)

  @impl Jido.ChatAction
  def invoke(client, signal, opts), do: Jido.Chat.Discord.Operations.invoke(:send_rich_message, client, signal, opts)
end
