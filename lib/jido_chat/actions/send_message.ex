defmodule Jido.Chat.SendMessage do
  @moduledoc "Native Jido Action for `Jido.Chat.Signal.SendMessage`. Input and output are data maps. Pass `%{client: client}` as context."
  use Jido.ChatAction, name: "chat_send_message", signal: Jido.Chat.Signal.SendMessage
end
