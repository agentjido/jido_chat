defmodule Jido.Chat.Signal.FetchMedia do
  @moduledoc """
  Typed query definition for `jido.chat.query.fetch_media`.

  Data uses the protocol version 1 string-key schema. No room subject is required; subject absence is permitted for the scoped media resource and its result.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :query,
    type: "jido.chat.query.fetch_media",
    dataschema: "urn:jido:chat:schema:query_fetch_media:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.from_json_schema(
        Jason.decode!(
          ~S|{"type":"object","properties":{"request_id":{"type":"string","minLength":1},"media_ref":{"type":"object","properties":{"id":{"type":"string","minLength":1},"scope":{"enum":["call"]},"binding_id":{"type":"string","minLength":1},"kind":{"enum":["file","media","stream","card","modal","result"]}},"required":["id","scope","binding_id","kind"],"additionalProperties":false},"thread_id":{"type":"string","minLength":1},"reply_to_id":{"type":"string","minLength":1},"format":{"enum":["plain","markdown","html"]}},"required":["request_id","media_ref"],"additionalProperties":false}|
        )
      )
end
