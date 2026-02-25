defmodule Jido.ChatTest do
  use ExUnit.Case
  doctest Jido.Chat

  test "greets the world" do
    assert Jido.Chat.hello() == :world
  end
end
