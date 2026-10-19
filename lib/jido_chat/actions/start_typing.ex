defmodule Jido.Chat.StartTyping do
  @moduledoc "Native Jido Action for `Jido.Chat.Signal.StartTyping`. Input and output use `%{signal: signal}`. Pass `%{client: client}` as context."
  use Jido.ChatAction, name: "chat_start_typing", signal: Jido.Chat.Signal.StartTyping
end
