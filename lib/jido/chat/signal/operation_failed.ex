defmodule Jido.Chat.Signal.OperationFailed do
  @moduledoc """
  Typed result definition for `jido.chat.operation.failed`.

  Data uses the protocol version 1 string-key schema. The operation target conversation subject, or absence for a non-room operation.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :result,
    type: "jido.chat.operation.failed",
    dataschema: "urn:jido:chat:schema:operation_failed:1",
    default_source: "urn:jido:chat:binding:YmluZGluZy9hbHBoYQ",
    schema:
      Zoi.from_json_schema(
        Jason.decode!(
          ~S|{"type":"object","properties":{"operation":{"enum":["send_message","send_file","post_message","edit_message","delete_message","start_typing","fetch_metadata","fetch_thread","fetch_message","get_user","fetch_subject","get_thread_participants","mark_as_read","fetch_media","add_reaction","remove_reaction","post_ephemeral","post_channel_message","stream","open_modal","load_options","fetch_messages","fetch_channel_messages","list_threads","open_thread","open_dm"]},"request_id":{"type":"string","minLength":1},"code":{"enum":["unsupported","provider_failure","invalid_provider_result","resource_expired","resource_cancelled","resource_failure"]},"retryable":{"type":"boolean"}},"required":["operation","request_id","code","retryable"],"additionalProperties":false}|
        )
      )
end
