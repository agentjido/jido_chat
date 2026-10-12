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
      Zoi.from_json_schema(
        Jason.decode!(
          ~S|{"type":"object","properties":{"item_id":{"type":"string","minLength":1},"delivery_id":{"type":"string","minLength":1},"room_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"code":{"enum":["invalid_item","unsupported_item","invalid_context","unsafe_data"]},"item_index":{"type":"integer","minimum":0},"provider_kind":{"type":"string"}},"required":["item_id","delivery_id","code","item_index"],"additionalProperties":false}|
        )
      )
end
