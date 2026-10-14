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
      Zoi.map(
        %{
          "item_id" => Zoi.string() |> Zoi.min(1),
          "delivery_id" => Zoi.string() |> Zoi.min(1),
          "room_id" => Zoi.string() |> Zoi.min(1),
          "participant_id" => Zoi.string() |> Zoi.min(1),
          "actor_id" =>
            Zoi.union([
              Zoi.string() |> Zoi.min(1),
              Zoi.null()
            ])
            |> Zoi.optional(),
          "bot_self" => Zoi.boolean(),
          "transition" =>
            Zoi.enum(["joined", "left", "removed", "role_changed", "restriction_changed", "unchanged", "unknown"]),
          "evidence" =>
            Zoi.enum(["explicit_join", "explicit_leave", "explicit_remove", "state_transition", "partial_transition"]),
          "previous" =>
            Zoi.union([
              Zoi.map(
                %{
                  "status" =>
                    Zoi.enum(["creator", "administrator", "member", "restricted", "left", "removed", "unknown"]),
                  "is_member" =>
                    Zoi.union([
                      Zoi.boolean(),
                      Zoi.null()
                    ]),
                  "role" =>
                    Zoi.union([
                      Zoi.string(),
                      Zoi.null()
                    ])
                    |> Zoi.optional(),
                  "restrictions" =>
                    Zoi.map(
                      %{
                        "can_send_messages" => Zoi.boolean() |> Zoi.optional(),
                        "can_send_audios" => Zoi.boolean() |> Zoi.optional(),
                        "can_send_documents" => Zoi.boolean() |> Zoi.optional(),
                        "can_send_photos" => Zoi.boolean() |> Zoi.optional(),
                        "can_send_videos" => Zoi.boolean() |> Zoi.optional(),
                        "can_send_video_notes" => Zoi.boolean() |> Zoi.optional(),
                        "can_send_voice_notes" => Zoi.boolean() |> Zoi.optional(),
                        "can_send_polls" => Zoi.boolean() |> Zoi.optional(),
                        "can_send_other_messages" => Zoi.boolean() |> Zoi.optional(),
                        "can_add_web_page_previews" => Zoi.boolean() |> Zoi.optional(),
                        "can_change_info" => Zoi.boolean() |> Zoi.optional(),
                        "can_invite_users" => Zoi.boolean() |> Zoi.optional(),
                        "can_pin_messages" => Zoi.boolean() |> Zoi.optional(),
                        "can_manage_topics" => Zoi.boolean() |> Zoi.optional(),
                        "can_react_to_messages" => Zoi.boolean() |> Zoi.optional(),
                        "can_edit_tag" => Zoi.boolean() |> Zoi.optional(),
                        "until_date" => Zoi.integer() |> Zoi.gte(0) |> Zoi.optional()
                      },
                      strict: true
                    )
                    |> Zoi.optional()
                },
                strict: true
              ),
              Zoi.null()
            ]),
          "current" =>
            Zoi.map(
              %{
                "status" =>
                  Zoi.enum(["creator", "administrator", "member", "restricted", "left", "removed", "unknown"]),
                "is_member" =>
                  Zoi.union([
                    Zoi.boolean(),
                    Zoi.null()
                  ]),
                "role" =>
                  Zoi.union([
                    Zoi.string(),
                    Zoi.null()
                  ])
                  |> Zoi.optional(),
                "restrictions" =>
                  Zoi.map(
                    %{
                      "can_send_messages" => Zoi.boolean() |> Zoi.optional(),
                      "can_send_audios" => Zoi.boolean() |> Zoi.optional(),
                      "can_send_documents" => Zoi.boolean() |> Zoi.optional(),
                      "can_send_photos" => Zoi.boolean() |> Zoi.optional(),
                      "can_send_videos" => Zoi.boolean() |> Zoi.optional(),
                      "can_send_video_notes" => Zoi.boolean() |> Zoi.optional(),
                      "can_send_voice_notes" => Zoi.boolean() |> Zoi.optional(),
                      "can_send_polls" => Zoi.boolean() |> Zoi.optional(),
                      "can_send_other_messages" => Zoi.boolean() |> Zoi.optional(),
                      "can_add_web_page_previews" => Zoi.boolean() |> Zoi.optional(),
                      "can_change_info" => Zoi.boolean() |> Zoi.optional(),
                      "can_invite_users" => Zoi.boolean() |> Zoi.optional(),
                      "can_pin_messages" => Zoi.boolean() |> Zoi.optional(),
                      "can_manage_topics" => Zoi.boolean() |> Zoi.optional(),
                      "can_react_to_messages" => Zoi.boolean() |> Zoi.optional(),
                      "can_edit_tag" => Zoi.boolean() |> Zoi.optional(),
                      "until_date" => Zoi.integer() |> Zoi.gte(0) |> Zoi.optional()
                    },
                    strict: true
                  )
                  |> Zoi.optional()
              },
              strict: true
            )
        },
        strict: true
      )
end
