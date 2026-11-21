defmodule Jido.Chat.TelegramTest do
  use ExUnit.Case, async: true

  test "adapter/0 returns the telegram adapter module" do
    assert Jido.Chat.Telegram.adapter() == Jido.Chat.Telegram.Adapter
  end
end
