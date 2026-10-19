defmodule Jido.Chat.FetchMessage do
  @moduledoc "Native Jido Action for `Jido.Chat.Signal.FetchMessage`. Input and output use `%{signal: signal}`. Pass `%{client: client}` as context."
  use Jido.ChatAction, name: "chat_fetch_message", signal: Jido.Chat.Signal.FetchMessage
end
