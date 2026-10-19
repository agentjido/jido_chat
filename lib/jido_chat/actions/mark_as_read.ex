defmodule Jido.Chat.MarkAsRead do
  @moduledoc "Native Jido Action for `Jido.Chat.Signal.MarkAsRead`. Input and output are data maps. Pass `%{client: client}` as context."
  use Jido.ChatAction, name: "chat_mark_as_read", signal: Jido.Chat.Signal.MarkAsRead
end
