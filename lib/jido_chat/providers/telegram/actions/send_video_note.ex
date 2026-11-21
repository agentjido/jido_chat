defmodule Jido.Chat.Telegram.SendVideoNote do
  @moduledoc """
  Runs one Telegram send_video_note operation with an explicit Client.

  Use `Jido.Exec.run/3`, Jido Flow, or a Router-selected Instruction with request
  data as input. Successful output is completion data. Use `reply/3` to build its
  Signal, or `Jido.Chat.execute/3` to execute a request Signal. Add
  `signal_definitions/0` to the host catalog.
  """
  alias Jido.Chat.Telegram.Signal.Schemas

  use Jido.ChatAction,
    name: "telegram_send_video_note",
    signal: Jido.Chat.Telegram.Signal.SendVideoNote,
    result_schema: Schemas.media_result()

  @impl Jido.ChatAction
  def invoke(client, signal, opts),
    do: Jido.Chat.Telegram.Operations.invoke(:send_video_note, client, signal, opts)
end
