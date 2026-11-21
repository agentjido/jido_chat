defmodule Jido.Chat.Telegram.Signal.SendDraft do
  @moduledoc "Typed Telegram send_draft request."
  alias Jido.Chat.Telegram.Signal.Schemas

  use Jido.Signal,
    type: "jido.chat.telegram.command.send_draft",
    dataschema: "urn:jido:chat:telegram:send_draft:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Schemas.request(%{
        "room_id" => Schemas.numeric_id(),
        "draft_id" => Zoi.integer() |> Zoi.min(1),
        "text" => Zoi.string() |> Zoi.min(1),
        "format" => Zoi.enum(["plain", "markdown", "html"]) |> Zoi.optional(),
        "thread_id" => Schemas.id() |> Zoi.optional()
      })
end
