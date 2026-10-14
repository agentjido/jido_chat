defmodule Jido.Chat.Signal.OperationCompleted do
  @moduledoc """
  Typed result definition for `jido.chat.operation.completed`.

  Data uses the protocol version 1 string-key schema. The completed operation conversation subject, or its user/resource scope; absence is permitted for non-room operations.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :result,
    type: "jido.chat.operation.completed",
    dataschema: "urn:jido:chat:schema:operation_completed:1",
    default_source: "urn:jido:chat:binding:YmluZGluZy9hbHBoYQ",
    schema:
      Zoi.union([
        Zoi.map(
          %{
            "operation" => Zoi.enum(["send_message"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "id" => Zoi.string() |> Zoi.min(1),
                    "room_id" => Zoi.string() |> Zoi.min(1),
                    "text" => Zoi.string() |> Zoi.optional(),
                    "sender" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "username" => Zoi.string() |> Zoi.optional(),
                          "display_name" => Zoi.string() |> Zoi.optional(),
                          "is_bot" => Zoi.boolean() |> Zoi.optional(),
                          "is_self" => Zoi.boolean() |> Zoi.optional()
                        },
                        strict: true
                      )
                      |> Zoi.optional(),
                    "thread_id" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ])
                      |> Zoi.optional(),
                    "reply_to_id" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ])
                      |> Zoi.optional(),
                    "media" =>
                      Zoi.array(
                        Zoi.map(
                          %{
                            "kind" => Zoi.enum(["image", "audio", "video", "file"]),
                            "resource_ref" =>
                              Zoi.map(
                                %{
                                  "id" => Zoi.string() |> Zoi.min(1),
                                  "scope" => Zoi.enum(["call"]),
                                  "binding_id" => Zoi.string() |> Zoi.min(1),
                                  "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                                },
                                strict: true
                              ),
                            "name" => Zoi.string() |> Zoi.optional(),
                            "media_type" => Zoi.string() |> Zoi.optional(),
                            "caption" => Zoi.string() |> Zoi.optional()
                          },
                          strict: true
                        )
                      )
                      |> Zoi.optional(),
                    "timestamp" => Zoi.string() |> Zoi.optional(),
                    "status" =>
                      Zoi.enum(["sent", "received", "updated", "deleted", "pending", "failed"]) |> Zoi.optional(),
                    "role" => Zoi.enum(["user", "assistant", "system", "tool"]) |> Zoi.optional()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["send_file"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "id" => Zoi.string() |> Zoi.min(1),
                    "room_id" => Zoi.string() |> Zoi.min(1),
                    "text" => Zoi.string() |> Zoi.optional(),
                    "sender" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "username" => Zoi.string() |> Zoi.optional(),
                          "display_name" => Zoi.string() |> Zoi.optional(),
                          "is_bot" => Zoi.boolean() |> Zoi.optional(),
                          "is_self" => Zoi.boolean() |> Zoi.optional()
                        },
                        strict: true
                      )
                      |> Zoi.optional(),
                    "thread_id" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ])
                      |> Zoi.optional(),
                    "reply_to_id" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ])
                      |> Zoi.optional(),
                    "media" =>
                      Zoi.array(
                        Zoi.map(
                          %{
                            "kind" => Zoi.enum(["image", "audio", "video", "file"]),
                            "resource_ref" =>
                              Zoi.map(
                                %{
                                  "id" => Zoi.string() |> Zoi.min(1),
                                  "scope" => Zoi.enum(["call"]),
                                  "binding_id" => Zoi.string() |> Zoi.min(1),
                                  "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                                },
                                strict: true
                              ),
                            "name" => Zoi.string() |> Zoi.optional(),
                            "media_type" => Zoi.string() |> Zoi.optional(),
                            "caption" => Zoi.string() |> Zoi.optional()
                          },
                          strict: true
                        )
                      )
                      |> Zoi.optional(),
                    "timestamp" => Zoi.string() |> Zoi.optional(),
                    "status" =>
                      Zoi.enum(["sent", "received", "updated", "deleted", "pending", "failed"]) |> Zoi.optional(),
                    "role" => Zoi.enum(["user", "assistant", "system", "tool"]) |> Zoi.optional()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["post_message"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "id" => Zoi.string() |> Zoi.min(1),
                    "room_id" => Zoi.string() |> Zoi.min(1),
                    "text" => Zoi.string() |> Zoi.optional(),
                    "sender" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "username" => Zoi.string() |> Zoi.optional(),
                          "display_name" => Zoi.string() |> Zoi.optional(),
                          "is_bot" => Zoi.boolean() |> Zoi.optional(),
                          "is_self" => Zoi.boolean() |> Zoi.optional()
                        },
                        strict: true
                      )
                      |> Zoi.optional(),
                    "thread_id" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ])
                      |> Zoi.optional(),
                    "reply_to_id" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ])
                      |> Zoi.optional(),
                    "media" =>
                      Zoi.array(
                        Zoi.map(
                          %{
                            "kind" => Zoi.enum(["image", "audio", "video", "file"]),
                            "resource_ref" =>
                              Zoi.map(
                                %{
                                  "id" => Zoi.string() |> Zoi.min(1),
                                  "scope" => Zoi.enum(["call"]),
                                  "binding_id" => Zoi.string() |> Zoi.min(1),
                                  "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                                },
                                strict: true
                              ),
                            "name" => Zoi.string() |> Zoi.optional(),
                            "media_type" => Zoi.string() |> Zoi.optional(),
                            "caption" => Zoi.string() |> Zoi.optional()
                          },
                          strict: true
                        )
                      )
                      |> Zoi.optional(),
                    "timestamp" => Zoi.string() |> Zoi.optional(),
                    "status" =>
                      Zoi.enum(["sent", "received", "updated", "deleted", "pending", "failed"]) |> Zoi.optional(),
                    "role" => Zoi.enum(["user", "assistant", "system", "tool"]) |> Zoi.optional()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["edit_message"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "id" => Zoi.string() |> Zoi.min(1),
                    "room_id" => Zoi.string() |> Zoi.min(1),
                    "text" => Zoi.string() |> Zoi.optional(),
                    "sender" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "username" => Zoi.string() |> Zoi.optional(),
                          "display_name" => Zoi.string() |> Zoi.optional(),
                          "is_bot" => Zoi.boolean() |> Zoi.optional(),
                          "is_self" => Zoi.boolean() |> Zoi.optional()
                        },
                        strict: true
                      )
                      |> Zoi.optional(),
                    "thread_id" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ])
                      |> Zoi.optional(),
                    "reply_to_id" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ])
                      |> Zoi.optional(),
                    "media" =>
                      Zoi.array(
                        Zoi.map(
                          %{
                            "kind" => Zoi.enum(["image", "audio", "video", "file"]),
                            "resource_ref" =>
                              Zoi.map(
                                %{
                                  "id" => Zoi.string() |> Zoi.min(1),
                                  "scope" => Zoi.enum(["call"]),
                                  "binding_id" => Zoi.string() |> Zoi.min(1),
                                  "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                                },
                                strict: true
                              ),
                            "name" => Zoi.string() |> Zoi.optional(),
                            "media_type" => Zoi.string() |> Zoi.optional(),
                            "caption" => Zoi.string() |> Zoi.optional()
                          },
                          strict: true
                        )
                      )
                      |> Zoi.optional(),
                    "timestamp" => Zoi.string() |> Zoi.optional(),
                    "status" =>
                      Zoi.enum(["sent", "received", "updated", "deleted", "pending", "failed"]) |> Zoi.optional(),
                    "role" => Zoi.enum(["user", "assistant", "system", "tool"]) |> Zoi.optional()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["delete_message"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "acknowledged" => Zoi.boolean()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["start_typing"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "acknowledged" => Zoi.boolean()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["fetch_metadata"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "id" => Zoi.string() |> Zoi.min(1),
                    "name" => Zoi.string() |> Zoi.optional(),
                    "kind" => Zoi.enum(["direct", "group", "channel", "thread", "unknown"]) |> Zoi.optional(),
                    "topic" => Zoi.string() |> Zoi.optional()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["fetch_thread"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "id" => Zoi.string() |> Zoi.min(1),
                    "room_id" => Zoi.string() |> Zoi.min(1),
                    "parent_message_id" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ])
                      |> Zoi.optional(),
                    "name" => Zoi.string() |> Zoi.optional(),
                    "delivery_room_ref" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ])
                      |> Zoi.optional()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["fetch_message"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "id" => Zoi.string() |> Zoi.min(1),
                    "room_id" => Zoi.string() |> Zoi.min(1),
                    "text" => Zoi.string() |> Zoi.optional(),
                    "sender" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "username" => Zoi.string() |> Zoi.optional(),
                          "display_name" => Zoi.string() |> Zoi.optional(),
                          "is_bot" => Zoi.boolean() |> Zoi.optional(),
                          "is_self" => Zoi.boolean() |> Zoi.optional()
                        },
                        strict: true
                      )
                      |> Zoi.optional(),
                    "thread_id" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ])
                      |> Zoi.optional(),
                    "reply_to_id" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ])
                      |> Zoi.optional(),
                    "media" =>
                      Zoi.array(
                        Zoi.map(
                          %{
                            "kind" => Zoi.enum(["image", "audio", "video", "file"]),
                            "resource_ref" =>
                              Zoi.map(
                                %{
                                  "id" => Zoi.string() |> Zoi.min(1),
                                  "scope" => Zoi.enum(["call"]),
                                  "binding_id" => Zoi.string() |> Zoi.min(1),
                                  "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                                },
                                strict: true
                              ),
                            "name" => Zoi.string() |> Zoi.optional(),
                            "media_type" => Zoi.string() |> Zoi.optional(),
                            "caption" => Zoi.string() |> Zoi.optional()
                          },
                          strict: true
                        )
                      )
                      |> Zoi.optional(),
                    "timestamp" => Zoi.string() |> Zoi.optional(),
                    "status" =>
                      Zoi.enum(["sent", "received", "updated", "deleted", "pending", "failed"]) |> Zoi.optional(),
                    "role" => Zoi.enum(["user", "assistant", "system", "tool"]) |> Zoi.optional()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["get_user"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "id" => Zoi.string() |> Zoi.min(1),
                    "username" => Zoi.string() |> Zoi.optional(),
                    "display_name" => Zoi.string() |> Zoi.optional(),
                    "is_bot" => Zoi.boolean() |> Zoi.optional(),
                    "is_self" => Zoi.boolean() |> Zoi.optional()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["fetch_subject"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "id" => Zoi.string() |> Zoi.min(1),
                    "kind" => Zoi.enum(["conversation", "thread", "message"]),
                    "room_id" => Zoi.string() |> Zoi.min(1),
                    "title" => Zoi.string() |> Zoi.optional()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["get_thread_participants"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "participants" =>
                      Zoi.array(
                        Zoi.map(
                          %{
                            "id" => Zoi.string() |> Zoi.min(1),
                            "username" => Zoi.string() |> Zoi.optional(),
                            "display_name" => Zoi.string() |> Zoi.optional(),
                            "is_bot" => Zoi.boolean() |> Zoi.optional(),
                            "is_self" => Zoi.boolean() |> Zoi.optional()
                          },
                          strict: true
                        )
                      ),
                    "complete" => Zoi.boolean(),
                    "scope" => Zoi.enum(["conversation", "thread", "observed"]),
                    "next_cursor" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ])
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["mark_as_read"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "acknowledged" => Zoi.boolean()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["fetch_media"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.map(
                %{
                  "resource_ref" =>
                    Zoi.map(
                      %{
                        "id" => Zoi.string() |> Zoi.min(1),
                        "scope" => Zoi.enum(["call"]),
                        "binding_id" => Zoi.string() |> Zoi.min(1),
                        "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                      },
                      strict: true
                    )
                },
                strict: true
              )
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["add_reaction"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "acknowledged" => Zoi.boolean()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["remove_reaction"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "acknowledged" => Zoi.boolean()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["post_ephemeral"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "id" => Zoi.string() |> Zoi.min(1),
                    "room_id" => Zoi.string() |> Zoi.min(1),
                    "text" => Zoi.string() |> Zoi.optional(),
                    "sender" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "username" => Zoi.string() |> Zoi.optional(),
                          "display_name" => Zoi.string() |> Zoi.optional(),
                          "is_bot" => Zoi.boolean() |> Zoi.optional(),
                          "is_self" => Zoi.boolean() |> Zoi.optional()
                        },
                        strict: true
                      )
                      |> Zoi.optional(),
                    "thread_id" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ])
                      |> Zoi.optional(),
                    "reply_to_id" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ])
                      |> Zoi.optional(),
                    "media" =>
                      Zoi.array(
                        Zoi.map(
                          %{
                            "kind" => Zoi.enum(["image", "audio", "video", "file"]),
                            "resource_ref" =>
                              Zoi.map(
                                %{
                                  "id" => Zoi.string() |> Zoi.min(1),
                                  "scope" => Zoi.enum(["call"]),
                                  "binding_id" => Zoi.string() |> Zoi.min(1),
                                  "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                                },
                                strict: true
                              ),
                            "name" => Zoi.string() |> Zoi.optional(),
                            "media_type" => Zoi.string() |> Zoi.optional(),
                            "caption" => Zoi.string() |> Zoi.optional()
                          },
                          strict: true
                        )
                      )
                      |> Zoi.optional(),
                    "timestamp" => Zoi.string() |> Zoi.optional(),
                    "status" =>
                      Zoi.enum(["sent", "received", "updated", "deleted", "pending", "failed"]) |> Zoi.optional(),
                    "role" => Zoi.enum(["user", "assistant", "system", "tool"]) |> Zoi.optional()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["post_channel_message"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "id" => Zoi.string() |> Zoi.min(1),
                    "room_id" => Zoi.string() |> Zoi.min(1),
                    "text" => Zoi.string() |> Zoi.optional(),
                    "sender" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "username" => Zoi.string() |> Zoi.optional(),
                          "display_name" => Zoi.string() |> Zoi.optional(),
                          "is_bot" => Zoi.boolean() |> Zoi.optional(),
                          "is_self" => Zoi.boolean() |> Zoi.optional()
                        },
                        strict: true
                      )
                      |> Zoi.optional(),
                    "thread_id" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ])
                      |> Zoi.optional(),
                    "reply_to_id" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ])
                      |> Zoi.optional(),
                    "media" =>
                      Zoi.array(
                        Zoi.map(
                          %{
                            "kind" => Zoi.enum(["image", "audio", "video", "file"]),
                            "resource_ref" =>
                              Zoi.map(
                                %{
                                  "id" => Zoi.string() |> Zoi.min(1),
                                  "scope" => Zoi.enum(["call"]),
                                  "binding_id" => Zoi.string() |> Zoi.min(1),
                                  "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                                },
                                strict: true
                              ),
                            "name" => Zoi.string() |> Zoi.optional(),
                            "media_type" => Zoi.string() |> Zoi.optional(),
                            "caption" => Zoi.string() |> Zoi.optional()
                          },
                          strict: true
                        )
                      )
                      |> Zoi.optional(),
                    "timestamp" => Zoi.string() |> Zoi.optional(),
                    "status" =>
                      Zoi.enum(["sent", "received", "updated", "deleted", "pending", "failed"]) |> Zoi.optional(),
                    "role" => Zoi.enum(["user", "assistant", "system", "tool"]) |> Zoi.optional()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["stream"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "id" => Zoi.string() |> Zoi.min(1),
                    "room_id" => Zoi.string() |> Zoi.min(1),
                    "text" => Zoi.string() |> Zoi.optional(),
                    "sender" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "username" => Zoi.string() |> Zoi.optional(),
                          "display_name" => Zoi.string() |> Zoi.optional(),
                          "is_bot" => Zoi.boolean() |> Zoi.optional(),
                          "is_self" => Zoi.boolean() |> Zoi.optional()
                        },
                        strict: true
                      )
                      |> Zoi.optional(),
                    "thread_id" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ])
                      |> Zoi.optional(),
                    "reply_to_id" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ])
                      |> Zoi.optional(),
                    "media" =>
                      Zoi.array(
                        Zoi.map(
                          %{
                            "kind" => Zoi.enum(["image", "audio", "video", "file"]),
                            "resource_ref" =>
                              Zoi.map(
                                %{
                                  "id" => Zoi.string() |> Zoi.min(1),
                                  "scope" => Zoi.enum(["call"]),
                                  "binding_id" => Zoi.string() |> Zoi.min(1),
                                  "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                                },
                                strict: true
                              ),
                            "name" => Zoi.string() |> Zoi.optional(),
                            "media_type" => Zoi.string() |> Zoi.optional(),
                            "caption" => Zoi.string() |> Zoi.optional()
                          },
                          strict: true
                        )
                      )
                      |> Zoi.optional(),
                    "timestamp" => Zoi.string() |> Zoi.optional(),
                    "status" =>
                      Zoi.enum(["sent", "received", "updated", "deleted", "pending", "failed"]) |> Zoi.optional(),
                    "role" => Zoi.enum(["user", "assistant", "system", "tool"]) |> Zoi.optional()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["open_modal"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
                    "opened" => Zoi.boolean()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["load_options"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "options" =>
                      Zoi.array(
                        Zoi.map(
                          %{
                            "label" => Zoi.string(),
                            "value" => Zoi.string(),
                            "description" => Zoi.string() |> Zoi.optional(),
                            "url" => Zoi.string() |> Zoi.optional()
                          },
                          strict: true
                        )
                      ),
                    "option_groups" =>
                      Zoi.array(
                        Zoi.map(
                          %{
                            "label" => Zoi.string(),
                            "options" =>
                              Zoi.array(
                                Zoi.map(
                                  %{
                                    "label" => Zoi.string(),
                                    "value" => Zoi.string(),
                                    "description" => Zoi.string() |> Zoi.optional(),
                                    "url" => Zoi.string() |> Zoi.optional()
                                  },
                                  strict: true
                                )
                              )
                          },
                          strict: true
                        )
                      )
                      |> Zoi.optional(),
                    "complete" => Zoi.boolean()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["fetch_messages"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "messages" =>
                      Zoi.array(
                        Zoi.map(
                          %{
                            "id" => Zoi.string() |> Zoi.min(1),
                            "room_id" => Zoi.string() |> Zoi.min(1),
                            "text" => Zoi.string() |> Zoi.optional(),
                            "sender" =>
                              Zoi.map(
                                %{
                                  "id" => Zoi.string() |> Zoi.min(1),
                                  "username" => Zoi.string() |> Zoi.optional(),
                                  "display_name" => Zoi.string() |> Zoi.optional(),
                                  "is_bot" => Zoi.boolean() |> Zoi.optional(),
                                  "is_self" => Zoi.boolean() |> Zoi.optional()
                                },
                                strict: true
                              )
                              |> Zoi.optional(),
                            "thread_id" =>
                              Zoi.union([
                                Zoi.string() |> Zoi.min(1),
                                Zoi.null()
                              ])
                              |> Zoi.optional(),
                            "reply_to_id" =>
                              Zoi.union([
                                Zoi.string() |> Zoi.min(1),
                                Zoi.null()
                              ])
                              |> Zoi.optional(),
                            "media" =>
                              Zoi.array(
                                Zoi.map(
                                  %{
                                    "kind" => Zoi.enum(["image", "audio", "video", "file"]),
                                    "resource_ref" =>
                                      Zoi.map(
                                        %{
                                          "id" => Zoi.string() |> Zoi.min(1),
                                          "scope" => Zoi.enum(["call"]),
                                          "binding_id" => Zoi.string() |> Zoi.min(1),
                                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                                        },
                                        strict: true
                                      ),
                                    "name" => Zoi.string() |> Zoi.optional(),
                                    "media_type" => Zoi.string() |> Zoi.optional(),
                                    "caption" => Zoi.string() |> Zoi.optional()
                                  },
                                  strict: true
                                )
                              )
                              |> Zoi.optional(),
                            "timestamp" => Zoi.string() |> Zoi.optional(),
                            "status" =>
                              Zoi.enum(["sent", "received", "updated", "deleted", "pending", "failed"])
                              |> Zoi.optional(),
                            "role" => Zoi.enum(["user", "assistant", "system", "tool"]) |> Zoi.optional()
                          },
                          strict: true
                        )
                      ),
                    "next_cursor" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ]),
                    "complete" => Zoi.boolean()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["fetch_channel_messages"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "messages" =>
                      Zoi.array(
                        Zoi.map(
                          %{
                            "id" => Zoi.string() |> Zoi.min(1),
                            "room_id" => Zoi.string() |> Zoi.min(1),
                            "text" => Zoi.string() |> Zoi.optional(),
                            "sender" =>
                              Zoi.map(
                                %{
                                  "id" => Zoi.string() |> Zoi.min(1),
                                  "username" => Zoi.string() |> Zoi.optional(),
                                  "display_name" => Zoi.string() |> Zoi.optional(),
                                  "is_bot" => Zoi.boolean() |> Zoi.optional(),
                                  "is_self" => Zoi.boolean() |> Zoi.optional()
                                },
                                strict: true
                              )
                              |> Zoi.optional(),
                            "thread_id" =>
                              Zoi.union([
                                Zoi.string() |> Zoi.min(1),
                                Zoi.null()
                              ])
                              |> Zoi.optional(),
                            "reply_to_id" =>
                              Zoi.union([
                                Zoi.string() |> Zoi.min(1),
                                Zoi.null()
                              ])
                              |> Zoi.optional(),
                            "media" =>
                              Zoi.array(
                                Zoi.map(
                                  %{
                                    "kind" => Zoi.enum(["image", "audio", "video", "file"]),
                                    "resource_ref" =>
                                      Zoi.map(
                                        %{
                                          "id" => Zoi.string() |> Zoi.min(1),
                                          "scope" => Zoi.enum(["call"]),
                                          "binding_id" => Zoi.string() |> Zoi.min(1),
                                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                                        },
                                        strict: true
                                      ),
                                    "name" => Zoi.string() |> Zoi.optional(),
                                    "media_type" => Zoi.string() |> Zoi.optional(),
                                    "caption" => Zoi.string() |> Zoi.optional()
                                  },
                                  strict: true
                                )
                              )
                              |> Zoi.optional(),
                            "timestamp" => Zoi.string() |> Zoi.optional(),
                            "status" =>
                              Zoi.enum(["sent", "received", "updated", "deleted", "pending", "failed"])
                              |> Zoi.optional(),
                            "role" => Zoi.enum(["user", "assistant", "system", "tool"]) |> Zoi.optional()
                          },
                          strict: true
                        )
                      ),
                    "next_cursor" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ]),
                    "complete" => Zoi.boolean()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["list_threads"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "threads" =>
                      Zoi.array(
                        Zoi.map(
                          %{
                            "id" => Zoi.string() |> Zoi.min(1),
                            "room_id" => Zoi.string() |> Zoi.min(1),
                            "parent_message_id" =>
                              Zoi.union([
                                Zoi.string() |> Zoi.min(1),
                                Zoi.null()
                              ])
                              |> Zoi.optional(),
                            "name" => Zoi.string() |> Zoi.optional(),
                            "delivery_room_ref" =>
                              Zoi.union([
                                Zoi.string() |> Zoi.min(1),
                                Zoi.null()
                              ])
                              |> Zoi.optional()
                          },
                          strict: true
                        )
                      ),
                    "next_cursor" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ]),
                    "complete" => Zoi.boolean()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["open_thread"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "id" => Zoi.string() |> Zoi.min(1),
                    "room_id" => Zoi.string() |> Zoi.min(1),
                    "parent_message_id" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ])
                      |> Zoi.optional(),
                    "name" => Zoi.string() |> Zoi.optional(),
                    "delivery_room_ref" =>
                      Zoi.union([
                        Zoi.string() |> Zoi.min(1),
                        Zoi.null()
                      ])
                      |> Zoi.optional()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        ),
        Zoi.map(
          %{
            "operation" => Zoi.enum(["open_dm"]),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "result" =>
              Zoi.union([
                Zoi.map(
                  %{
                    "id" => Zoi.string() |> Zoi.min(1),
                    "name" => Zoi.string() |> Zoi.optional(),
                    "kind" => Zoi.enum(["direct", "group", "channel", "thread", "unknown"]) |> Zoi.optional(),
                    "topic" => Zoi.string() |> Zoi.optional()
                  },
                  strict: true
                ),
                Zoi.map(
                  %{
                    "resource_ref" =>
                      Zoi.map(
                        %{
                          "id" => Zoi.string() |> Zoi.min(1),
                          "scope" => Zoi.enum(["call"]),
                          "binding_id" => Zoi.string() |> Zoi.min(1),
                          "kind" => Zoi.enum(["file", "media", "stream", "card", "modal", "result"])
                        },
                        strict: true
                      )
                  },
                  strict: true
                )
              ])
          },
          strict: true
        )
      ])
end
