defmodule Jido.Chat.EditMessage do
  @moduledoc "Native Jido Action for `Jido.Chat.Signal.EditMessage`. Input and output use `%{signal: signal}`. Pass `%{client: client}` as context."
  use Jido.ChatAction, name: "chat_edit_message", signal: Jido.Chat.Signal.EditMessage
end
