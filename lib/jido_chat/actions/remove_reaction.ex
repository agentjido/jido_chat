defmodule Jido.Chat.RemoveReaction do
  @moduledoc "Native Jido Action for `Jido.Chat.Signal.RemoveReaction`. Input and output are data maps. Pass `%{client: client}` as context."
  use Jido.ChatAction, name: "chat_remove_reaction", signal: Jido.Chat.Signal.RemoveReaction
end
