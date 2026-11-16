defmodule Jido.Chat.CreateThread do
  @moduledoc "Creates a named chat thread. Agent routes defer provider execution until after commit."

  use Jido.ChatAction,
    name: "chat_create_thread",
    description: "Create a named chat thread",
    signal: Jido.Chat.Signal.CreateThread
end
