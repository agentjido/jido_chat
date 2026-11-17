defmodule Jido.Chat.Signal.MembershipChanged do
  @moduledoc """
  Typed fact definition for `jido.chat.membership.changed`.

  Data uses the protocol version 1 string-key schema. The client-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Signal,
    type: "jido.chat.membership.changed",
    dataschema: "urn:jido:chat:schema:membership_changed:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Jido.Joi.map(
        %{
          "item_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "delivery_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "room_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "participant_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "actor_id" =>
            Jido.Joi.union([
              Jido.Joi.string() |> Jido.Joi.min(1),
              Jido.Joi.literal(nil)
            ])
            |> Jido.Joi.optional(),
          "bot_self" => Jido.Joi.boolean(),
          "transition" =>
            Jido.Joi.enum(["joined", "left", "removed", "role_changed", "restriction_changed", "unchanged", "unknown"]),
          "evidence" =>
            Jido.Joi.enum([
              "explicit_join",
              "explicit_leave",
              "explicit_remove",
              "state_transition",
              "partial_transition"
            ]),
          "previous" =>
            Jido.Joi.union([
              Jido.Joi.map(
                %{
                  "status" =>
                    Jido.Joi.enum(["creator", "administrator", "member", "restricted", "left", "removed", "unknown"]),
                  "is_member" =>
                    Jido.Joi.union([
                      Jido.Joi.boolean(),
                      Jido.Joi.literal(nil)
                    ]),
                  "role" =>
                    Jido.Joi.union([
                      Jido.Joi.string(),
                      Jido.Joi.literal(nil)
                    ])
                    |> Jido.Joi.optional(),
                  "restrictions" =>
                    Jido.Joi.map(
                      %{
                        "can_send_messages" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                        "can_send_audios" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                        "can_send_documents" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                        "can_send_photos" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                        "can_send_videos" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                        "can_send_video_notes" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                        "can_send_voice_notes" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                        "can_send_polls" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                        "can_send_other_messages" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                        "can_add_web_page_previews" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                        "can_change_info" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                        "can_invite_users" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                        "can_pin_messages" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                        "can_manage_topics" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                        "can_react_to_messages" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                        "can_edit_tag" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                        "until_date" => Jido.Joi.integer() |> Jido.Joi.min(0) |> Jido.Joi.optional()
                      },
                      unrecognized_keys: :error
                    )
                    |> Jido.Joi.optional()
                },
                unrecognized_keys: :error
              ),
              Jido.Joi.literal(nil)
            ]),
          "current" =>
            Jido.Joi.map(
              %{
                "status" =>
                  Jido.Joi.enum(["creator", "administrator", "member", "restricted", "left", "removed", "unknown"]),
                "is_member" =>
                  Jido.Joi.union([
                    Jido.Joi.boolean(),
                    Jido.Joi.literal(nil)
                  ]),
                "role" =>
                  Jido.Joi.union([
                    Jido.Joi.string(),
                    Jido.Joi.literal(nil)
                  ])
                  |> Jido.Joi.optional(),
                "restrictions" =>
                  Jido.Joi.map(
                    %{
                      "can_send_messages" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                      "can_send_audios" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                      "can_send_documents" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                      "can_send_photos" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                      "can_send_videos" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                      "can_send_video_notes" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                      "can_send_voice_notes" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                      "can_send_polls" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                      "can_send_other_messages" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                      "can_add_web_page_previews" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                      "can_change_info" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                      "can_invite_users" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                      "can_pin_messages" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                      "can_manage_topics" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                      "can_react_to_messages" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                      "can_edit_tag" => Jido.Joi.boolean() |> Jido.Joi.optional(),
                      "until_date" => Jido.Joi.integer() |> Jido.Joi.min(0) |> Jido.Joi.optional()
                    },
                    unrecognized_keys: :error
                  )
                  |> Jido.Joi.optional()
              },
              unrecognized_keys: :error
            )
        },
        unrecognized_keys: :error
      )
end
