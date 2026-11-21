defmodule Jido.Chat.Telegram.Signal.SendVideoNote do
  @moduledoc "Typed Telegram send_video_note request."
  alias Jido.Chat.Telegram.Signal.Schemas

  use Jido.Signal,
    type: "jido.chat.telegram.command.send_video_note",
    dataschema: "urn:jido:chat:telegram:send_video_note:1",
    default_source: "urn:jido:chat:producer:local",
    schema: Schemas.media_request(false)
end
