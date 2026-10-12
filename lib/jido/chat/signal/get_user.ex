defmodule Jido.Chat.Signal.GetUser do
  @moduledoc """
  Typed query definition for `jido.chat.query.get_user`.

  Data uses the protocol version 1 string-key schema. No room subject is required; subject absence is permitted for user lookup and its result.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :query,
    type: "jido.chat.query.get_user",
    dataschema: "urn:jido:chat:schema:query_get_user:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.from_json_schema(
        Jason.decode!(
          ~S|{"type":"object","properties":{"request_id":{"type":"string","minLength":1},"user_id":{"type":"string","minLength":1},"thread_id":{"type":"string","minLength":1},"reply_to_id":{"type":"string","minLength":1},"format":{"enum":["plain","markdown","html"]}},"required":["request_id","user_id"],"additionalProperties":false}|
        )
      )
end
