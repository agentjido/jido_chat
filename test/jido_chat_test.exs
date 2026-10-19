defmodule Jido.ChatTest do
  use ExUnit.Case, async: true

  test "the public facade exposes native operations and pure rendering" do
    assert length(Jido.Chat.actions()) == 23
    assert Jido.Chat.emoji(":thumbsup:") == "👍"

    for {name, arity} <- [message: 1, new_room: 1, new_participant: 1, text: 1] do
      refute function_exported?(Jido.Chat, name, arity)
    end
  end

  test "SDK startup metadata does not start Jido or register Chat processes" do
    refute :jido in Application.spec(:jido_chat, :applications)
    assert Application.spec(:jido_chat, :registered) == []
    assert Application.spec(:jido_chat, :mod) == []
  end
end
