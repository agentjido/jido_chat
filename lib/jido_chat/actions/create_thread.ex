defmodule Jido.Chat.CreateThread do
  @moduledoc "Native Jido Action for `Jido.Chat.Signal.CreateThread`. Input and output use `%{signal: signal}`. Pass `%{client: client}` as context."
  use Jido.ChatAction, name: "chat_create_thread", signal: Jido.Chat.Signal.CreateThread
end
