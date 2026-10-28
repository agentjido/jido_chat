defmodule Jido.Chat.AI do
  @moduledoc "Pure conversion of portable Chat messages to AI history maps."

  alias Jido.Chat.Message

  @doc "Converts ordered Chat messages to role and content maps."
  @spec to_messages([Message.t()]) :: [map()]
  def to_messages(messages) when is_list(messages) do
    Enum.map(messages, fn %Message{} = message ->
      %{
        "role" => Atom.to_string(message.role),
        "content" => Message.fallback_text(message)
      }
    end)
  end
end
