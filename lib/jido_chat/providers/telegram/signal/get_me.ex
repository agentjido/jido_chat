defmodule Jido.Chat.Telegram.Signal.GetMe do
  @moduledoc "Typed Telegram get_me request."
  alias Jido.Chat.Telegram.Signal.Schemas

  use Jido.Signal,
    type: "jido.chat.telegram.query.get_me",
    dataschema: "urn:jido:chat:telegram:get_me:1",
    default_source: "urn:jido:chat:producer:local",
    schema: Schemas.request(%{})
end
