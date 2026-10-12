defmodule Jido.Chat.Signal.AssistantThreadStarted do
  @moduledoc """
  Typed fact definition for `jido.chat.assistant.thread_started`.

  Data uses the protocol version 1 string-key schema. The binding-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :fact,
    type: "jido.chat.assistant.thread_started",
    dataschema: "urn:jido:chat:schema:assistant_thread_started:1",
    default_source: "urn:jido:chat:binding:YmluZGluZy9hbHBoYQ",
    schema:
      Zoi.from_json_schema(
        Jason.decode!(
          ~S|{"type":"object","properties":{"item_id":{"type":"string","minLength":1},"delivery_id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"thread_id":{"type":"string","minLength":1},"actor_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"context":{"type":"object","properties":{"channel_id":{"type":"string","minLength":1},"team_id":{"type":"string","minLength":1},"enterprise_id":{"type":"string","minLength":1}},"required":[],"additionalProperties":false}},"required":["item_id","delivery_id","room_id","thread_id"],"additionalProperties":false}|
        )
      )
end
