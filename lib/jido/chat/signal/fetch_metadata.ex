defmodule Jido.Chat.Signal.FetchMetadata do
  @moduledoc """
  Typed query definition for `jido.chat.query.fetch_metadata`.

  Data uses the protocol version 1 string-key schema. Request may omit subject. If present, it must equal conversation_subject(binding_id, room_id). A room result uses that conversation subject.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :query,
    type: "jido.chat.query.fetch_metadata",
    dataschema: "urn:jido:chat:schema:query_fetch_metadata:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.from_json_schema(
        Jason.decode!(
          ~S|{"type":"object","properties":{"request_id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"thread_id":{"type":"string","minLength":1},"reply_to_id":{"type":"string","minLength":1},"format":{"enum":["plain","markdown","html"]}},"required":["request_id","room_id"],"additionalProperties":false}|
        )
      )
end
