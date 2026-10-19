defmodule Jido.Chat.FetchMessages do
  @moduledoc "Native Jido Action for `Jido.Chat.Signal.FetchMessages`. Input and output use `%{signal: signal}`. Pass `%{client: client}` as context."
  use Jido.ChatAction, name: "chat_fetch_messages", signal: Jido.Chat.Signal.FetchMessages
end
