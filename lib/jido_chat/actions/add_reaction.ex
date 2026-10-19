defmodule Jido.Chat.AddReaction do
  @moduledoc "Native Jido Action for `Jido.Chat.Signal.AddReaction`. Input and output are data maps. Pass `%{client: client}` as context."
  use Jido.ChatAction, name: "chat_add_reaction", signal: Jido.Chat.Signal.AddReaction
end
