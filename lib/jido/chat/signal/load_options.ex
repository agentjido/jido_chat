defmodule Jido.Chat.Signal.LoadOptions do
  @moduledoc """
  Typed query definition for `jido.chat.query.load_options`.

  Data uses the protocol version 1 string-key schema. Use the binding-scoped room subject only when an interaction room is known; absence is permitted for an interaction with no room.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :query,
    type: "jido.chat.query.load_options",
    dataschema: "urn:jido:chat:schema:query_load_options:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.from_json_schema(
        Jason.decode!(
          ~S|{"type":"object","properties":{"request_id":{"type":"string","minLength":1},"interaction_id":{"type":"string","minLength":1},"query":{"type":"string"},"thread_id":{"type":"string","minLength":1},"reply_to_id":{"type":"string","minLength":1},"format":{"enum":["plain","markdown","html"]},"action_id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"view_id":{"type":"string","minLength":1},"user_id":{"type":"string","minLength":1},"limit":{"type":"integer","minimum":1}},"required":["request_id","interaction_id","query"],"additionalProperties":false}|
        )
      )
end
