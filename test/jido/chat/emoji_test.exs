defmodule Jido.Chat.EmojiTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Emoji

  test "render keeps built-in tokens and preserves unknown named tokens" do
    assert Emoji.render(":thumbs_up:") == "👍"
    assert Emoji.render(":custom-flag:") == ":custom-flag:"
  end

  test "put_custom supports custom names without requiring preexisting atoms" do
    registry = Emoji.put_custom(%{}, "custom-emoji", "🎯")

    assert Emoji.render(":custom-emoji:", custom: registry) == "🎯"
  end
end
