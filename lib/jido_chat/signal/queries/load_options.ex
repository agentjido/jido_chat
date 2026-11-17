defmodule Jido.Chat.Signal.LoadOptions do
  @moduledoc "Typed query for load_options. Unsupported request fields are rejected."
  use Jido.Signal,
    type: "jido.chat.query.load_options",
    dataschema: "urn:jido:chat:schema:query_load_options:3",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Jido.Joi.map(
        %{
          "client_id" => Jido.Chat.Signal.Schemas.id(),
          "request_id" => Jido.Chat.Signal.Schemas.id(),
          "interaction_id" => Jido.Chat.Signal.Schemas.id(),
          "query" => Jido.Joi.string(),
          "action_id" => Jido.Chat.Signal.Schemas.id() |> Jido.Joi.optional(),
          "room_id" => Jido.Chat.Signal.Schemas.id() |> Jido.Joi.optional(),
          "view_id" => Jido.Chat.Signal.Schemas.id() |> Jido.Joi.optional(),
          "user_id" => Jido.Chat.Signal.Schemas.id() |> Jido.Joi.optional(),
          "limit" => Jido.Joi.integer() |> Jido.Joi.min(1) |> Jido.Joi.optional()
        },
        unrecognized_keys: :error
      )
end
