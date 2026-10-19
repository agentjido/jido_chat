defmodule Jido.Chat.FetchThread do
  @moduledoc "Native Jido Action for `Jido.Chat.Signal.FetchThread`. Input and output use `%{signal: signal}`. Pass `%{client: client}` as context."
  use Jido.ChatAction, name: "chat_fetch_thread", signal: Jido.Chat.Signal.FetchThread
end
