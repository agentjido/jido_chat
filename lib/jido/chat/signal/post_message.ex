defmodule Jido.Chat.Signal.PostMessage do
  @moduledoc """
  Typed command definition for `jido.chat.command.post_message`.

  Data uses the protocol version 1 string-key schema. Request may omit subject. If present, it must equal conversation_subject(binding_id, room_id). A room result uses that conversation subject.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :command,
    type: "jido.chat.command.post_message",
    dataschema: "urn:jido:chat:schema:command_post_message:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.from_json_schema(
        Jason.decode!(
          ~S|{"type":"object","properties":{"request_id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"content":{"oneOf":[{"type":"object","properties":{"kind":{"enum":["text","markdown"]},"text":{"type":"string"}},"required":["kind","text"],"additionalProperties":false},{"type":"object","properties":{"kind":{"enum":["card","stream","media"]},"resource_ref":{"type":"object","properties":{"id":{"type":"string","minLength":1},"scope":{"enum":["call"]},"binding_id":{"type":"string","minLength":1},"kind":{"enum":["file","media","stream","card","modal","result"]}},"required":["id","scope","binding_id","kind"],"additionalProperties":false},"fallback_text":{"type":"string"},"caption":{"type":"string"}},"required":["kind","resource_ref"],"additionalProperties":false}]},"thread_id":{"type":"string","minLength":1},"reply_to_id":{"type":"string","minLength":1},"format":{"enum":["plain","markdown","html"]}},"required":["request_id","room_id","content"],"additionalProperties":false}|
        )
      )
end
