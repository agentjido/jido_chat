defmodule Jido.Chat.Signal.ReactionAdded do
  @moduledoc """
  Typed fact definition for `jido.chat.reaction.added`.

  Data uses the protocol version 1 string-key schema. The binding-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :fact,
    type: "jido.chat.reaction.added",
    dataschema: "urn:jido:chat:schema:reaction_added:1",
    default_source: "urn:jido:chat:binding:YmluZGluZy9hbHBoYQ",
    schema:
      Zoi.from_json_schema(
        Jason.decode!(
          ~S|{"type":"object","properties":{"item_id":{"type":"string","minLength":1},"delivery_id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"message_id":{"type":"string","minLength":1},"actor_id":{"type":"string","minLength":1},"reaction":{"type":"string","minLength":1},"thread_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]}},"required":["item_id","delivery_id","room_id","message_id","actor_id","reaction"],"additionalProperties":false}|
        )
      )
end
