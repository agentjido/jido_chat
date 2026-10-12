defmodule Jido.Chat.Signal.SlashCommandReceived do
  @moduledoc """
  Typed fact definition for `jido.chat.slash_command.received`.

  Data uses the protocol version 1 string-key schema. The binding-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :fact,
    type: "jido.chat.slash_command.received",
    dataschema: "urn:jido:chat:schema:slash_command_received:1",
    default_source: "urn:jido:chat:binding:YmluZGluZy9hbHBoYQ",
    schema:
      Zoi.from_json_schema(
        Jason.decode!(
          ~S|{"type":"object","properties":{"item_id":{"type":"string","minLength":1},"delivery_id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"interaction_id":{"type":"string","minLength":1},"command":{"type":"string","minLength":1},"text":{"type":"string"},"actor_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"thread_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]}},"required":["item_id","delivery_id","room_id","interaction_id","command","text"],"additionalProperties":false}|
        )
      )
end
