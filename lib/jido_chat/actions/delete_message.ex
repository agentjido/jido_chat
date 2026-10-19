defmodule Jido.Chat.DeleteMessage do
  @moduledoc "Native Jido Action for `Jido.Chat.Signal.DeleteMessage`. Input and output use `%{signal: signal}`. Pass `%{client: client}` as context."
  use Jido.ChatAction, name: "chat_delete_message", signal: Jido.Chat.Signal.DeleteMessage
end
