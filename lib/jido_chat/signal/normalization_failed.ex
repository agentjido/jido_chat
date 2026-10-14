defmodule Jido.Chat.Signal.NormalizationFailed do
  @moduledoc """
  Typed fact definition for `jido.chat.normalization.failed`.

  Data uses the protocol version 1 string-key schema. The binding-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :fact,
    type: "jido.chat.normalization.failed",
    dataschema: "urn:jido:chat:schema:normalization_failed:1",
    default_source: "urn:jido:chat:binding:YmluZGluZy9hbHBoYQ",
    schema:
      Zoi.map(
        %{
          "item_id" => Zoi.string() |> Zoi.min(1),
          "delivery_id" => Zoi.string() |> Zoi.min(1),
          "room_id" =>
            Zoi.union([
              Zoi.string() |> Zoi.min(1),
              Zoi.null()
            ])
            |> Zoi.optional(),
          "code" => Zoi.enum(["invalid_item", "unsupported_item", "invalid_context", "unsafe_data"]),
          "item_index" => Zoi.integer() |> Zoi.gte(0),
          "provider_kind" => Zoi.string() |> Zoi.optional()
        },
        unrecognized_keys: :error
      )
end
