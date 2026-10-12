defmodule Jido.Chat.Signal.MembershipChanged do
  @moduledoc """
  Typed fact definition for `jido.chat.membership.changed`.

  Data uses the protocol version 1 string-key schema. The binding-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :fact,
    type: "jido.chat.membership.changed",
    dataschema: "urn:jido:chat:schema:membership_changed:1",
    default_source: "urn:jido:chat:binding:YmluZGluZy9hbHBoYQ",
    schema:
      Zoi.from_json_schema(
        Jason.decode!(
          ~S|{"type":"object","properties":{"item_id":{"type":"string","minLength":1},"delivery_id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"participant_id":{"type":"string","minLength":1},"actor_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"bot_self":{"type":"boolean"},"transition":{"enum":["joined","left","removed","role_changed","restriction_changed","unchanged","unknown"]},"evidence":{"enum":["explicit_join","explicit_leave","explicit_remove","state_transition","partial_transition"]},"previous":{"anyOf":[{"type":"object","properties":{"status":{"enum":["creator","administrator","member","restricted","left","removed","unknown"]},"is_member":{"anyOf":[{"type":"boolean"},{"type":"null"}]},"role":{"anyOf":[{"type":"string"},{"type":"null"}]},"restrictions":{"type":"object","properties":{"can_send_messages":{"type":"boolean"},"can_send_audios":{"type":"boolean"},"can_send_documents":{"type":"boolean"},"can_send_photos":{"type":"boolean"},"can_send_videos":{"type":"boolean"},"can_send_video_notes":{"type":"boolean"},"can_send_voice_notes":{"type":"boolean"},"can_send_polls":{"type":"boolean"},"can_send_other_messages":{"type":"boolean"},"can_add_web_page_previews":{"type":"boolean"},"can_change_info":{"type":"boolean"},"can_invite_users":{"type":"boolean"},"can_pin_messages":{"type":"boolean"},"can_manage_topics":{"type":"boolean"}},"required":[],"additionalProperties":false}},"required":["status","is_member"],"additionalProperties":false},{"type":"null"}]},"current":{"type":"object","properties":{"status":{"enum":["creator","administrator","member","restricted","left","removed","unknown"]},"is_member":{"anyOf":[{"type":"boolean"},{"type":"null"}]},"role":{"anyOf":[{"type":"string"},{"type":"null"}]},"restrictions":{"type":"object","properties":{"can_send_messages":{"type":"boolean"},"can_send_audios":{"type":"boolean"},"can_send_documents":{"type":"boolean"},"can_send_photos":{"type":"boolean"},"can_send_videos":{"type":"boolean"},"can_send_video_notes":{"type":"boolean"},"can_send_voice_notes":{"type":"boolean"},"can_send_polls":{"type":"boolean"},"can_send_other_messages":{"type":"boolean"},"can_add_web_page_previews":{"type":"boolean"},"can_change_info":{"type":"boolean"},"can_invite_users":{"type":"boolean"},"can_pin_messages":{"type":"boolean"},"can_manage_topics":{"type":"boolean"}},"required":[],"additionalProperties":false}},"required":["status","is_member"],"additionalProperties":false}},"required":["item_id","delivery_id","room_id","participant_id","bot_self","transition","evidence","previous","current"],"additionalProperties":false}|
        )
      )
end
