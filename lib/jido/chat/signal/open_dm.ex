defmodule Jido.Chat.Signal.OpenDm do
  @moduledoc """
  Typed command definition for `jido.chat.command.open_dm`.

  Data uses the protocol version 1 string-key schema. Request has no conversation subject. Success uses conversation_subject(binding_id, result.id) for the opened DM; failure may omit subject.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :command,
    type: "jido.chat.command.open_dm",
    dataschema: "urn:jido:chat:schema:command_open_dm:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.from_json_schema(
        Jason.decode!(
          ~S|{"type":"object","properties":{"request_id":{"type":"string","minLength":1},"user_id":{"type":"string","minLength":1},"thread_id":{"type":"string","minLength":1},"reply_to_id":{"type":"string","minLength":1},"format":{"enum":["plain","markdown","html"]}},"required":["request_id","user_id"],"additionalProperties":false}|
        )
      )
end
