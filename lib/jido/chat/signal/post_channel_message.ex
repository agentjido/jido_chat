defmodule Jido.Chat.Signal.PostChannelMessage do
  @moduledoc """
  Typed command definition for `jido.chat.command.post_channel_message`.

  Data uses the protocol version 1 string-key schema. Request may omit subject. If present, it must equal conversation_subject(binding_id, room_id). A room result uses that conversation subject.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :command,
    type: "jido.chat.command.post_channel_message",
    dataschema: "urn:jido:chat:schema:command_post_channel_message:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.from_json_schema(
        Jason.decode!(
          ~S|{"type":"object","properties":{"request_id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"text":{"type":"string"},"thread_id":{"type":"string","minLength":1},"reply_to_id":{"type":"string","minLength":1},"format":{"enum":["plain","markdown","html"]}},"required":["request_id","room_id","text"],"additionalProperties":false}|
        )
      )
end
