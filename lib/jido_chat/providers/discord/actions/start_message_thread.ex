defmodule Jido.Chat.Discord.StartMessageThread do
  @moduledoc "Start a Discord message thread through an explicit Client."
  use Jido.ChatAction,
    name: "discord_start_message_thread",
    signal: Jido.Chat.Discord.Signal.StartMessageThread,
    result_schema: Jido.Chat.Signal.Schemas.result(:created_thread)

  @impl Jido.ChatAction
  def invoke(client, signal, opts), do: Jido.Chat.Discord.Operations.invoke(:start_message_thread, client, signal, opts)
end
