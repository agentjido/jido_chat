defmodule Jido.Chat.Signal.OptionsRequested do
  @moduledoc """
  Typed fact definition for `jido.chat.options.requested`.

  Data uses the protocol version 1 string-key schema. The binding-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :fact,
    type: "jido.chat.options.requested",
    dataschema: "urn:jido:chat:schema:options_requested:1",
    default_source: "urn:jido:chat:binding:YmluZGluZy9hbHBoYQ",
    schema:
      Zoi.map(
        %{
          "item_id" => Zoi.string() |> Zoi.min(1),
          "delivery_id" => Zoi.string() |> Zoi.min(1),
          "room_id" => Zoi.string() |> Zoi.min(1),
          "interaction_id" => Zoi.string() |> Zoi.min(1),
          "action_id" => Zoi.string() |> Zoi.min(1),
          "query" => Zoi.string(),
          "actor_id" =>
            Zoi.union([
              Zoi.string() |> Zoi.min(1),
              Zoi.null()
            ])
            |> Zoi.optional(),
          "view_id" =>
            Zoi.union([
              Zoi.string() |> Zoi.min(1),
              Zoi.null()
            ])
            |> Zoi.optional(),
          "limit" => Zoi.integer() |> Zoi.gte(1) |> Zoi.optional()
        },
        unrecognized_keys: :error
      )
end
