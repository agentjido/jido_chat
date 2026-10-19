defmodule Jido.Chat.OpenDm do
  @moduledoc "Native Jido Action for `Jido.Chat.Signal.OpenDm`. Input and output are data maps. Pass `%{client: client}` as context."
  use Jido.ChatAction, name: "chat_open_dm", signal: Jido.Chat.Signal.OpenDm
end
