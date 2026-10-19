defmodule Jido.Chat.ListThreads do
  @moduledoc "Native Jido Action for `Jido.Chat.Signal.ListThreads`. Input and output are data maps. Pass `%{client: client}` as context."
  use Jido.ChatAction, name: "chat_list_threads", signal: Jido.Chat.Signal.ListThreads
end
