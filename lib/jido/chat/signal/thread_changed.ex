defmodule Jido.Chat.Signal.ThreadChanged do
  @moduledoc """
  Typed fact definition for `jido.chat.thread.changed`.

  Data uses the protocol version 1 string-key schema. The binding-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :fact,
    type: "jido.chat.thread.changed",
    dataschema: "urn:jido:chat:schema:thread_changed:1",
    default_source: "urn:jido:chat:binding:YmluZGluZy9hbHBoYQ",
    schema:
      Zoi.from_json_schema(
        Jason.decode!(
          ~S|{"type":"object","properties":{"item_id":{"type":"string","minLength":1},"delivery_id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"thread_id":{"type":"string","minLength":1},"parent_message_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"actor_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"name":{"type":"string"},"change":{"enum":["updated","reopened","closed"]}},"required":["item_id","delivery_id","room_id","thread_id","change"],"additionalProperties":false}|
        )
      )
end
