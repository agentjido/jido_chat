defmodule Jido.Chat.GetUser do
  @moduledoc "Native Jido Action for `Jido.Chat.Signal.GetUser`. Input and output use `%{signal: signal}`. Pass `%{client: client}` as context."
  use Jido.ChatAction, name: "chat_get_user", signal: Jido.Chat.Signal.GetUser
end
