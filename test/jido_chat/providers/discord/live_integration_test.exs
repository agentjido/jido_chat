defmodule Jido.Chat.Discord.LiveIntegrationTest do
  use Jido.Chat.LiveCase,
    profile: Jido.Chat.Discord.LiveFixture,
    mode: :legacy,
    group: :gateway
end
