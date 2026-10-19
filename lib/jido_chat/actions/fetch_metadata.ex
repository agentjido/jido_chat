defmodule Jido.Chat.FetchMetadata do
  @moduledoc "Native Jido Action for `Jido.Chat.Signal.FetchMetadata`. Input and output are data maps. Pass `%{client: client}` as context."
  use Jido.ChatAction, name: "chat_fetch_metadata", signal: Jido.Chat.Signal.FetchMetadata
end
