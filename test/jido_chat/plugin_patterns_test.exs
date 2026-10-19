defmodule Jido.Chat.PluginPatternsTest do
  use ExUnit.Case, async: true
  alias Jido.Chat.Plugin.Patterns

  test "selection is a union and each pattern must select a declared type" do
    types = ["jido.chat.message.received", "jido.chat.reaction.added"]
    patterns = ["jido.chat.message.*", "jido.chat.reaction.*"]
    assert Patterns.valid?(patterns, types)
    assert Patterns.selected?(hd(types), patterns)
    refute Patterns.selected?("jido.chat.command.send_message", patterns)

    for invalid <- [nil, [], ["jido.chat.message.*", "other.*"], ["jido..chat"], [42], "jido.chat.**.**"] do
      refute Patterns.valid?(invalid, types)
    end
  end

  test "overlap checks wildcard languages rather than a sample catalog" do
    for {left, right} <- [
          {"jido.chat.**", "jido.chat.message.*"},
          {"**", "jido.chat.future.*"},
          {"jido.chat.**.command.*", "jido.chat.**.command.*.*"},
          {"jido.chat.**.command.*", "jido.chat.command.send_message"},
          {"jido.chat.**.future", "jido.*.**.future"},
          {"jido.chat.**", "jido.chat"},
          {"jido.chat.message.*", "jido.chat.message.*"}
        ] do
      assert Patterns.overlap?(left, right)
      assert Patterns.overlap?(right, left)
    end

    for {left, right} <- [
          {"jido.chat.message.*", "jido.chat.reaction.*"},
          {"jido.chat.command.*", "jido.chat.command.*.*"},
          {"other.**", "other.*"},
          {"jido.chat.message", "jido.chat.message.*"},
          {"jido.chat.*.x", "jido.chat.*.y"}
        ] do
      refute Patterns.overlap?(left, right)
    end
  end
end
