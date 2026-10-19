defmodule Jido.Chat.PostEphemeral do
  @moduledoc "Native Jido Action for `Jido.Chat.Signal.PostEphemeral`. Input and output use `%{signal: signal}`. Pass `%{client: client}` as context."
  use Jido.ChatAction, name: "chat_post_ephemeral", signal: Jido.Chat.Signal.PostEphemeral
end
