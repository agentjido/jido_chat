defmodule Jido.Chat.Signal.LoadOptions do
  @moduledoc "Typed query for load_options. Unsupported request fields are rejected."
  use Jido.Signal,
    type: "jido.chat.query.load_options",
    dataschema: "urn:jido:chat:schema:query_load_options:3",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "client_id" => Jido.Chat.Signal.Schemas.id(),
          "request_id" => Jido.Chat.Signal.Schemas.id(),
          "interaction_id" => Jido.Chat.Signal.Schemas.id(),
          "query" => Zoi.string(),
          "action_id" => Jido.Chat.Signal.Schemas.id() |> Zoi.optional(),
          "room_id" => Jido.Chat.Signal.Schemas.id() |> Zoi.optional(),
          "view_id" => Jido.Chat.Signal.Schemas.id() |> Zoi.optional(),
          "user_id" => Jido.Chat.Signal.Schemas.id() |> Zoi.optional(),
          "limit" => Zoi.integer() |> Zoi.min(1) |> Zoi.optional()
        },
        unrecognized_keys: :error
      )
end
