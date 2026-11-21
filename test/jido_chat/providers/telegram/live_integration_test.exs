defmodule Jido.Chat.Telegram.LiveIntegrationTest do
  use Jido.Chat.LiveCase,
    profile: Jido.Chat.Telegram.LiveFixture,
    mode: :legacy,
    group: :actions,
    legacy_tag: :telegram_live
end
