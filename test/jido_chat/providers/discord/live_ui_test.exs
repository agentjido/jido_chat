defmodule Jido.Chat.Discord.LiveUITest do
  use Jido.Chat.LiveCase,
    profile: Jido.Chat.Discord.LiveFixture,
    mode: {:legacy, "RUN_LIVE_DISCORD_UI"},
    group: :ui
end
