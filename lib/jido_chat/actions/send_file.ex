defmodule Jido.Chat.SendFile do
  @moduledoc "Native Jido Action for `Jido.Chat.Signal.SendFile`. Input and output are data maps. Pass `%{client: client}` as context."
  use Jido.ChatAction, name: "chat_send_file", signal: Jido.Chat.Signal.SendFile
end
