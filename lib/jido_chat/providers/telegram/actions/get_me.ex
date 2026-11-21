defmodule Jido.Chat.Telegram.GetMe do
  @moduledoc """
  Runs one Telegram get_me operation with an explicit Client.

  Use `Jido.Exec.run/3`, Jido Flow, or a Router-selected Instruction with request
  data as input. Successful output is completion data. Use `reply/3` to build its
  Signal, or `Jido.Chat.execute/3` to execute a request Signal. Add
  `signal_definitions/0` to the host catalog.
  """
  alias Jido.Chat.Telegram.Signal.Schemas

  use Jido.ChatAction,
    name: "telegram_get_me",
    signal: Jido.Chat.Telegram.Signal.GetMe,
    result_schema: Schemas.user_result()

  @impl Jido.ChatAction
  def invoke(client, signal, opts),
    do: Jido.Chat.Telegram.Operations.invoke(:get_me, client, signal, opts)
end
