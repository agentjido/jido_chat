defmodule Jido.Chat.Telegram.Signal.SendAnimation do
  @moduledoc "Typed Telegram send_animation request."
  alias Jido.Chat.Telegram.Signal.Schemas

  use Jido.Signal,
    type: "jido.chat.telegram.command.send_animation",
    dataschema: "urn:jido:chat:telegram:send_animation:1",
    default_source: "urn:jido:chat:producer:local",
    schema: Schemas.media_request()
end
