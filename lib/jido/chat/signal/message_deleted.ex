defmodule Jido.Chat.Signal.MessageDeleted do
  @moduledoc """
  Typed fact definition for `jido.chat.message.deleted`.

  Data uses the protocol version 1 string-key schema. The binding-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :fact,
    type: "jido.chat.message.deleted",
    dataschema: "urn:jido:chat:schema:message_deleted:1",
    default_source: "urn:jido:chat:binding:YmluZGluZy9hbHBoYQ",
    schema:
      Zoi.from_json_schema(
        Jason.decode!(
          ~S|{"type":"object","properties":{"item_id":{"type":"string","minLength":1},"delivery_id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"message_id":{"type":"string","minLength":1},"actor_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"thread_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"timestamp":{"type":"string"}},"required":["item_id","delivery_id","room_id","message_id"],"additionalProperties":false}|
        )
      )
end
