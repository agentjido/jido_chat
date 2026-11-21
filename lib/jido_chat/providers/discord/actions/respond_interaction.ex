defmodule Jido.Chat.Discord.RespondInteraction do
  @moduledoc "Send a message, deferred response, update, or modal for a Discord interaction."
  use Jido.ChatAction,
    name: "discord_respond_interaction",
    signal: Jido.Chat.Discord.Signal.RespondInteraction,
    result_schema: Jido.Chat.Signal.Schemas.result(:acknowledgement)

  @impl Jido.ChatAction
  def invoke(client, signal, opts),
    do: Jido.Chat.Discord.Operations.invoke(:respond_interaction, client, signal, opts)
end
