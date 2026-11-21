defmodule Jido.Chat.Telegram.Signal.SendSticker do
  @moduledoc "Typed Telegram send_sticker request."
  alias Jido.Chat.Telegram.Signal.Schemas

  use Jido.Signal,
    type: "jido.chat.telegram.command.send_sticker",
    dataschema: "urn:jido:chat:telegram:send_sticker:1",
    default_source: "urn:jido:chat:producer:local",
    schema: Schemas.media_request(false)
end
