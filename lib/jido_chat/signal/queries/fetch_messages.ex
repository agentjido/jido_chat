defmodule Jido.Chat.Signal.FetchMessages do
  @moduledoc "Typed query for fetch_messages. Unsupported request fields are rejected."
  use Jido.Signal,
    type: "jido.chat.query.fetch_messages",
    dataschema: "urn:jido:chat:schema:query_fetch_messages:3",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Jido.Joi.map(
        %{
          "client_id" => Jido.Chat.Signal.Schemas.id(),
          "request_id" => Jido.Chat.Signal.Schemas.id(),
          "room_id" => Jido.Chat.Signal.Schemas.id(),
          "thread_id" => Jido.Chat.Signal.Schemas.id() |> Jido.Joi.optional(),
          "cursor" => Jido.Chat.Signal.Schemas.optional_id(),
          "limit" => Jido.Joi.integer() |> Jido.Joi.min(1) |> Jido.Joi.optional(),
          "direction" => Jido.Joi.enum(["forward", "backward"]) |> Jido.Joi.optional()
        },
        unrecognized_keys: :error
      )
end
