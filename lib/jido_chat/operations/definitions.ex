defmodule Jido.Chat.Operations.Definitions do
  @moduledoc false
  @operations Map.new([
                {"jido.chat.command.send_message",
                 {Jido.Chat.Signal.SendMessage, :send_message, ["room_id", "text"], :message,
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
                          unrecognized_keys: :error
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
                                  unrecognized_keys: :error
                                ),
                              "name" => Zoi.string() |> Zoi.optional(),
                              "media_type" => Zoi.string() |> Zoi.optional(),
                              "caption" => Zoi.string() |> Zoi.optional()
                            },
                            unrecognized_keys: :error
                          )
                        )
                        |> Zoi.optional(),
                      "timestamp" => Zoi.string() |> Zoi.optional(),
                      "status" =>
                        Zoi.enum(["sent", "received", "updated", "deleted", "pending", "failed"]) |> Zoi.optional(),
                      "role" => Zoi.enum(["user", "assistant", "system", "tool"]) |> Zoi.optional()
                    },
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.command.send_file",
                 {Jido.Chat.Signal.SendFile, :send_file, ["room_id", "resource_ref"], :message,
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
                          unrecognized_keys: :error
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
                                  unrecognized_keys: :error
                                ),
                              "name" => Zoi.string() |> Zoi.optional(),
                              "media_type" => Zoi.string() |> Zoi.optional(),
                              "caption" => Zoi.string() |> Zoi.optional()
                            },
                            unrecognized_keys: :error
                          )
                        )
                        |> Zoi.optional(),
                      "timestamp" => Zoi.string() |> Zoi.optional(),
                      "status" =>
                        Zoi.enum(["sent", "received", "updated", "deleted", "pending", "failed"]) |> Zoi.optional(),
                      "role" => Zoi.enum(["user", "assistant", "system", "tool"]) |> Zoi.optional()
                    },
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.command.post_message",
                 {Jido.Chat.Signal.PostMessage, :post_message, ["room_id", "content"], :message,
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
                          unrecognized_keys: :error
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
                                  unrecognized_keys: :error
                                ),
                              "name" => Zoi.string() |> Zoi.optional(),
                              "media_type" => Zoi.string() |> Zoi.optional(),
                              "caption" => Zoi.string() |> Zoi.optional()
                            },
                            unrecognized_keys: :error
                          )
                        )
                        |> Zoi.optional(),
                      "timestamp" => Zoi.string() |> Zoi.optional(),
                      "status" =>
                        Zoi.enum(["sent", "received", "updated", "deleted", "pending", "failed"]) |> Zoi.optional(),
                      "role" => Zoi.enum(["user", "assistant", "system", "tool"]) |> Zoi.optional()
                    },
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.command.edit_message",
                 {Jido.Chat.Signal.EditMessage, :edit_message, ["room_id", "message_id", "text"], :message,
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
                          unrecognized_keys: :error
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
                                  unrecognized_keys: :error
                                ),
                              "name" => Zoi.string() |> Zoi.optional(),
                              "media_type" => Zoi.string() |> Zoi.optional(),
                              "caption" => Zoi.string() |> Zoi.optional()
                            },
                            unrecognized_keys: :error
                          )
                        )
                        |> Zoi.optional(),
                      "timestamp" => Zoi.string() |> Zoi.optional(),
                      "status" =>
                        Zoi.enum(["sent", "received", "updated", "deleted", "pending", "failed"]) |> Zoi.optional(),
                      "role" => Zoi.enum(["user", "assistant", "system", "tool"]) |> Zoi.optional()
                    },
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.command.delete_message",
                 {Jido.Chat.Signal.DeleteMessage, :delete_message, ["room_id", "message_id"], :acknowledgement,
                  Zoi.map(
                    %{
                      "acknowledged" => Zoi.boolean()
                    },
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.command.start_typing",
                 {Jido.Chat.Signal.StartTyping, :start_typing, ["room_id"], :acknowledgement,
                  Zoi.map(
                    %{
                      "acknowledged" => Zoi.boolean()
                    },
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.query.fetch_metadata",
                 {Jido.Chat.Signal.FetchMetadata, :fetch_metadata, ["room_id"], :conversation,
                  Zoi.map(
                    %{
                      "id" => Zoi.string() |> Zoi.min(1),
                      "name" => Zoi.string() |> Zoi.optional(),
                      "kind" => Zoi.enum(["direct", "group", "channel", "thread", "unknown"]) |> Zoi.optional(),
                      "topic" => Zoi.string() |> Zoi.optional()
                    },
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.query.fetch_thread",
                 {Jido.Chat.Signal.FetchThread, :fetch_thread, ["room_id"], :thread,
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
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.query.fetch_message",
                 {Jido.Chat.Signal.FetchMessage, :fetch_message, ["room_id", "message_id"], :message,
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
                          unrecognized_keys: :error
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
                                  unrecognized_keys: :error
                                ),
                              "name" => Zoi.string() |> Zoi.optional(),
                              "media_type" => Zoi.string() |> Zoi.optional(),
                              "caption" => Zoi.string() |> Zoi.optional()
                            },
                            unrecognized_keys: :error
                          )
                        )
                        |> Zoi.optional(),
                      "timestamp" => Zoi.string() |> Zoi.optional(),
                      "status" =>
                        Zoi.enum(["sent", "received", "updated", "deleted", "pending", "failed"]) |> Zoi.optional(),
                      "role" => Zoi.enum(["user", "assistant", "system", "tool"]) |> Zoi.optional()
                    },
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.query.get_user",
                 {Jido.Chat.Signal.GetUser, :get_user, ["user_id"], :user,
                  Zoi.map(
                    %{
                      "id" => Zoi.string() |> Zoi.min(1),
                      "username" => Zoi.string() |> Zoi.optional(),
                      "display_name" => Zoi.string() |> Zoi.optional(),
                      "is_bot" => Zoi.boolean() |> Zoi.optional(),
                      "is_self" => Zoi.boolean() |> Zoi.optional()
                    },
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.query.fetch_subject",
                 {Jido.Chat.Signal.FetchSubject, :fetch_subject, ["room_id"], :subject,
                  Zoi.map(
                    %{
                      "id" => Zoi.string() |> Zoi.min(1),
                      "kind" => Zoi.enum(["conversation", "thread", "message"]),
                      "room_id" => Zoi.string() |> Zoi.min(1),
                      "title" => Zoi.string() |> Zoi.optional()
                    },
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.query.get_thread_participants",
                 {Jido.Chat.Signal.GetThreadParticipants, :get_thread_participants, ["room_id"], :participants,
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
                            unrecognized_keys: :error
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
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.command.mark_as_read",
                 {Jido.Chat.Signal.MarkAsRead, :mark_as_read, ["room_id", "message_id"], :acknowledgement,
                  Zoi.map(
                    %{
                      "acknowledged" => Zoi.boolean()
                    },
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.query.fetch_media",
                 {Jido.Chat.Signal.FetchMedia, :fetch_media, ["media_ref"], :resource,
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
                          unrecognized_keys: :error
                        )
                    },
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.command.add_reaction",
                 {Jido.Chat.Signal.AddReaction, :add_reaction, ["room_id", "message_id", "reaction"], :acknowledgement,
                  Zoi.map(
                    %{
                      "acknowledged" => Zoi.boolean()
                    },
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.command.remove_reaction",
                 {Jido.Chat.Signal.RemoveReaction, :remove_reaction, ["room_id", "message_id", "reaction"],
                  :acknowledgement,
                  Zoi.map(
                    %{
                      "acknowledged" => Zoi.boolean()
                    },
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.command.post_ephemeral",
                 {Jido.Chat.Signal.PostEphemeral, :post_ephemeral, ["room_id", "user_id", "text"], :message,
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
                          unrecognized_keys: :error
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
                                  unrecognized_keys: :error
                                ),
                              "name" => Zoi.string() |> Zoi.optional(),
                              "media_type" => Zoi.string() |> Zoi.optional(),
                              "caption" => Zoi.string() |> Zoi.optional()
                            },
                            unrecognized_keys: :error
                          )
                        )
                        |> Zoi.optional(),
                      "timestamp" => Zoi.string() |> Zoi.optional(),
                      "status" =>
                        Zoi.enum(["sent", "received", "updated", "deleted", "pending", "failed"]) |> Zoi.optional(),
                      "role" => Zoi.enum(["user", "assistant", "system", "tool"]) |> Zoi.optional()
                    },
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.command.post_channel_message",
                 {Jido.Chat.Signal.PostChannelMessage, :post_channel_message, ["room_id", "text"], :message,
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
                          unrecognized_keys: :error
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
                                  unrecognized_keys: :error
                                ),
                              "name" => Zoi.string() |> Zoi.optional(),
                              "media_type" => Zoi.string() |> Zoi.optional(),
                              "caption" => Zoi.string() |> Zoi.optional()
                            },
                            unrecognized_keys: :error
                          )
                        )
                        |> Zoi.optional(),
                      "timestamp" => Zoi.string() |> Zoi.optional(),
                      "status" =>
                        Zoi.enum(["sent", "received", "updated", "deleted", "pending", "failed"]) |> Zoi.optional(),
                      "role" => Zoi.enum(["user", "assistant", "system", "tool"]) |> Zoi.optional()
                    },
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.command.stream",
                 {Jido.Chat.Signal.Stream, :stream, ["room_id", "resource_ref"], :message,
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
                          unrecognized_keys: :error
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
                                  unrecognized_keys: :error
                                ),
                              "name" => Zoi.string() |> Zoi.optional(),
                              "media_type" => Zoi.string() |> Zoi.optional(),
                              "caption" => Zoi.string() |> Zoi.optional()
                            },
                            unrecognized_keys: :error
                          )
                        )
                        |> Zoi.optional(),
                      "timestamp" => Zoi.string() |> Zoi.optional(),
                      "status" =>
                        Zoi.enum(["sent", "received", "updated", "deleted", "pending", "failed"]) |> Zoi.optional(),
                      "role" => Zoi.enum(["user", "assistant", "system", "tool"]) |> Zoi.optional()
                    },
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.command.open_modal",
                 {Jido.Chat.Signal.OpenModal, :open_modal, ["room_id", "modal"], :modal,
                  Zoi.map(
                    %{
                      "id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
                      "opened" => Zoi.boolean()
                    },
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.query.load_options",
                 {Jido.Chat.Signal.LoadOptions, :load_options, ["interaction_id", "query"], :options,
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
                            unrecognized_keys: :error
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
                                    unrecognized_keys: :error
                                  )
                                )
                            },
                            unrecognized_keys: :error
                          )
                        )
                        |> Zoi.optional(),
                      "complete" => Zoi.boolean()
                    },
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.query.fetch_messages",
                 {Jido.Chat.Signal.FetchMessages, :fetch_messages, ["room_id"], :message_page,
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
                                  unrecognized_keys: :error
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
                                          unrecognized_keys: :error
                                        ),
                                      "name" => Zoi.string() |> Zoi.optional(),
                                      "media_type" => Zoi.string() |> Zoi.optional(),
                                      "caption" => Zoi.string() |> Zoi.optional()
                                    },
                                    unrecognized_keys: :error
                                  )
                                )
                                |> Zoi.optional(),
                              "timestamp" => Zoi.string() |> Zoi.optional(),
                              "status" =>
                                Zoi.enum(["sent", "received", "updated", "deleted", "pending", "failed"])
                                |> Zoi.optional(),
                              "role" => Zoi.enum(["user", "assistant", "system", "tool"]) |> Zoi.optional()
                            },
                            unrecognized_keys: :error
                          )
                        ),
                      "next_cursor" =>
                        Zoi.union([
                          Zoi.string() |> Zoi.min(1),
                          Zoi.null()
                        ]),
                      "complete" => Zoi.boolean()
                    },
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.query.fetch_channel_messages",
                 {Jido.Chat.Signal.FetchChannelMessages, :fetch_channel_messages, ["room_id"], :message_page,
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
                                  unrecognized_keys: :error
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
                                          unrecognized_keys: :error
                                        ),
                                      "name" => Zoi.string() |> Zoi.optional(),
                                      "media_type" => Zoi.string() |> Zoi.optional(),
                                      "caption" => Zoi.string() |> Zoi.optional()
                                    },
                                    unrecognized_keys: :error
                                  )
                                )
                                |> Zoi.optional(),
                              "timestamp" => Zoi.string() |> Zoi.optional(),
                              "status" =>
                                Zoi.enum(["sent", "received", "updated", "deleted", "pending", "failed"])
                                |> Zoi.optional(),
                              "role" => Zoi.enum(["user", "assistant", "system", "tool"]) |> Zoi.optional()
                            },
                            unrecognized_keys: :error
                          )
                        ),
                      "next_cursor" =>
                        Zoi.union([
                          Zoi.string() |> Zoi.min(1),
                          Zoi.null()
                        ]),
                      "complete" => Zoi.boolean()
                    },
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.query.list_threads",
                 {Jido.Chat.Signal.ListThreads, :list_threads, ["room_id"], :thread_page,
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
                            unrecognized_keys: :error
                          )
                        ),
                      "next_cursor" =>
                        Zoi.union([
                          Zoi.string() |> Zoi.min(1),
                          Zoi.null()
                        ]),
                      "complete" => Zoi.boolean()
                    },
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.command.open_thread",
                 {Jido.Chat.Signal.OpenThread, :open_thread, ["room_id", "message_id"], :thread,
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
                    unrecognized_keys: :error
                  )}},
                {"jido.chat.command.open_dm",
                 {Jido.Chat.Signal.OpenDm, :open_dm, ["user_id"], :conversation,
                  Zoi.map(
                    %{
                      "id" => Zoi.string() |> Zoi.min(1),
                      "name" => Zoi.string() |> Zoi.optional(),
                      "kind" => Zoi.enum(["direct", "group", "channel", "thread", "unknown"]) |> Zoi.optional(),
                      "topic" => Zoi.string() |> Zoi.optional()
                    },
                    unrecognized_keys: :error
                  )}}
              ])
  @doc false
  @spec lookup(String.t()) :: tuple() | nil
  def lookup(type), do: Map.get(@operations, type)
  @doc false
  @spec all() :: map()
  def all, do: @operations
end
