defmodule Jido.Chat.OpenModal do
  @moduledoc "Native Jido Action for `Jido.Chat.Signal.OpenModal`. Input and output use `%{signal: signal}`. Pass `%{client: client}` as context."
  use Jido.ChatAction, name: "chat_open_modal", signal: Jido.Chat.Signal.OpenModal
end
