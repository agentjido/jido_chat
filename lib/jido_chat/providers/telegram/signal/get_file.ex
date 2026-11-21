defmodule Jido.Chat.Telegram.Signal.GetFile do
  @moduledoc "Typed Telegram get_file request."
  alias Jido.Chat.Telegram.Signal.Schemas

  use Jido.Signal,
    type: "jido.chat.telegram.query.get_file",
    dataschema: "urn:jido:chat:telegram:get_file:1",
    default_source: "urn:jido:chat:producer:local",
    schema: Schemas.request(%{"resource_ref" => Schemas.reference()})
end
