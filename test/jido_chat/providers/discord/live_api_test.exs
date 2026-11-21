defmodule Jido.Chat.Discord.LiveAPITest do
  use Jido.Chat.LiveCase,
    profile: Jido.Chat.Discord.LiveFixture,
    mode: :legacy,
    group: :api
end
