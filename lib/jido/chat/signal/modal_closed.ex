defmodule Jido.Chat.Signal.ModalClosed do
  @moduledoc """
  Typed fact definition for `jido.chat.modal.closed`.

  Data uses the protocol version 1 string-key schema. The binding-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :fact,
    type: "jido.chat.modal.closed",
    dataschema: "urn:jido:chat:schema:modal_closed:1",
    default_source: "urn:jido:chat:binding:YmluZGluZy9hbHBoYQ",
    schema:
      Zoi.from_json_schema(
        Jason.decode!(
          ~S|{"type":"object","properties":{"item_id":{"type":"string","minLength":1},"delivery_id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"interaction_id":{"type":"string","minLength":1},"view_id":{"type":"string","minLength":1},"callback_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"actor_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]}},"required":["item_id","delivery_id","room_id","interaction_id","view_id"],"additionalProperties":false}|
        )
      )
end
