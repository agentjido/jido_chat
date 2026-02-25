defmodule JidoChatTest do
  use ExUnit.Case
  doctest JidoChat

  test "greets the world" do
    assert JidoChat.hello() == :world
  end
end
