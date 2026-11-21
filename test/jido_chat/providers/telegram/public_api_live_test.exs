defmodule Jido.Chat.Telegram.PublicAPILiveTest do
  use Jido.Chat.LiveCase,
    profile: Jido.Chat.Telegram.LiveFixture,
    mode: :legacy,
    group: :public_api,
    legacy_tag: :chat_public_api_live
end
