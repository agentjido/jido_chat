defmodule Jido.Chat.Signal.ReceiptReceived do
  @moduledoc """
  Typed fact definition for `jido.chat.receipt.received`.

  Data uses the protocol version 1 string-key schema. The binding-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :fact,
    type: "jido.chat.receipt.received",
    dataschema: "urn:jido:chat:schema:receipt_received:1",
    default_source: "urn:jido:chat:binding:YmluZGluZy9hbHBoYQ",
    schema:
      Zoi.from_json_schema(
        Jason.decode!(
          ~S|{"type":"object","properties":{"item_id":{"type":"string","minLength":1},"delivery_id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"message_ids":{"type":"array","items":{"type":"string","minLength":1}},"actor_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"receipt":{"enum":["delivered","read"]},"timestamp":{"type":"string"}},"required":["item_id","delivery_id","room_id","message_ids","receipt"],"additionalProperties":false}|
        )
      )
end
