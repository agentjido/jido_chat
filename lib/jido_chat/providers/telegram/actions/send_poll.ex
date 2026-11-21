defmodule Jido.Chat.Telegram.SendPoll do
  @moduledoc """
  Native Telegram poll Action built with the public Chat extension point.

  Run with `Jido.Exec.run/3` or use this Action in a Jido Flow. Add
  `signal_definitions/0` to a host catalog for its request and result Signals.
  """
  alias Jido.Chat.Telegram.Signal.Schemas

  use Jido.ChatAction,
    name: "telegram_send_poll",
    signal: Jido.Chat.Telegram.Signal.SendPoll,
    result_schema: Schemas.poll_result()

  @impl Jido.ChatAction
  def invoke(client, signal, opts),
    do: Jido.Chat.Telegram.Operations.invoke(:send_poll, client, signal, opts)
end
