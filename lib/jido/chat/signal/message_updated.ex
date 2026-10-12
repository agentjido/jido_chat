defmodule Jido.Chat.Signal.MessageUpdated do
  @moduledoc """
  Typed fact definition for `jido.chat.message.updated`.

  Data uses the protocol version 1 string-key schema. The binding-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :fact,
    type: "jido.chat.message.updated",
    dataschema: "urn:jido:chat:schema:message_updated:1",
    default_source: "urn:jido:chat:binding:YmluZGluZy9hbHBoYQ",
    schema:
      Zoi.from_json_schema(
        Jason.decode!(
          ~S|{"type":"object","properties":{"item_id":{"type":"string","minLength":1},"delivery_id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"message_id":{"type":"string","minLength":1},"sender":{"type":"object","properties":{"id":{"type":"string","minLength":1},"username":{"type":"string"},"display_name":{"type":"string"},"is_bot":{"type":"boolean"},"is_self":{"type":"boolean"}},"required":["id"],"additionalProperties":false},"text":{"type":"string"},"thread_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"media":{"type":"array","items":{"type":"object","properties":{"kind":{"enum":["image","audio","video","file"]},"resource_ref":{"type":"object","properties":{"id":{"type":"string","minLength":1},"scope":{"enum":["call"]},"binding_id":{"type":"string","minLength":1},"kind":{"enum":["file","media","stream","card","modal","result"]}},"required":["id","scope","binding_id","kind"],"additionalProperties":false},"name":{"type":"string"},"media_type":{"type":"string"},"caption":{"type":"string"}},"required":["kind","resource_ref"],"additionalProperties":false}},"timestamp":{"type":"string"}},"required":["item_id","delivery_id","room_id","message_id","text"],"additionalProperties":false}|
        )
      )
end
