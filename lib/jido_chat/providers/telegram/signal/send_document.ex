defmodule Jido.Chat.Telegram.Signal.SendDocument do
  @moduledoc "Typed Telegram send_document request."
  alias Jido.Chat.Telegram.Signal.Schemas

  use Jido.Signal,
    type: "jido.chat.telegram.command.send_document",
    dataschema: "urn:jido:chat:telegram:send_document:1",
    default_source: "urn:jido:chat:producer:local",
    schema: Schemas.media_request()
end
