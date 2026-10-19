defmodule Jido.Chat.LoadOptions do
  @moduledoc "Native Jido Action for `Jido.Chat.Signal.LoadOptions`. Input and output use `%{signal: signal}`. Pass `%{client: client}` as context."
  use Jido.ChatAction, name: "chat_load_options", signal: Jido.Chat.Signal.LoadOptions
end
