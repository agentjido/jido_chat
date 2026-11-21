defmodule Jido.Chat.Telegram.Signal.SendPhoto do
  @moduledoc "Typed Telegram send_photo request."
  alias Jido.Chat.Telegram.Signal.Schemas

  use Jido.Signal,
    type: "jido.chat.telegram.command.send_photo",
    dataschema: "urn:jido:chat:telegram:send_photo:1",
    default_source: "urn:jido:chat:producer:local",
    schema: Schemas.media_request()
end
