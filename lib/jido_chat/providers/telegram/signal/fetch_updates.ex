defmodule Jido.Chat.Telegram.Signal.FetchUpdates do
  @moduledoc "Typed Telegram fetch_updates request."
  alias Jido.Chat.Telegram.Signal.Schemas

  use Jido.Signal,
    type: "jido.chat.telegram.query.fetch_updates",
    dataschema: "urn:jido:chat:telegram:fetch_updates:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Schemas.request(%{
        "offset" => Zoi.integer() |> Zoi.min(0) |> Zoi.optional(),
        "limit" => Zoi.integer() |> Zoi.min(1) |> Zoi.max(100) |> Zoi.optional(),
        "timeout" => Zoi.integer() |> Zoi.min(0) |> Zoi.max(50) |> Zoi.optional(),
        "allowed_updates" => Zoi.array(Schemas.id()) |> Zoi.optional()
      })
end
