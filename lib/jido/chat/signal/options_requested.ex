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
      Zoi.from_json_schema(
        Jason.decode!(
          ~S|{"type":"object","properties":{"item_id":{"type":"string","minLength":1},"delivery_id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"interaction_id":{"type":"string","minLength":1},"action_id":{"type":"string","minLength":1},"query":{"type":"string"},"actor_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"view_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"limit":{"type":"integer","minimum":1}},"required":["item_id","delivery_id","room_id","interaction_id","action_id","query"],"additionalProperties":false}|
        )
      )
end
