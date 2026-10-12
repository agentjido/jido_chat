defmodule Jido.Chat.Operations.Definitions do
  @moduledoc false
  @operations Map.new([
                {"jido.chat.command.send_message",
                 {Jido.Chat.Signal.SendMessage, :send_message, ["room_id", "text"], :message,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"text":{"type":"string"},"sender":{"type":"object","properties":{"id":{"type":"string","minLength":1},"username":{"type":"string"},"display_name":{"type":"string"},"is_bot":{"type":"boolean"},"is_self":{"type":"boolean"}},"required":["id"],"additionalProperties":false},"thread_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"reply_to_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"media":{"type":"array","items":{"type":"object","properties":{"kind":{"enum":["image","audio","video","file"]},"resource_ref":{"type":"object","properties":{"id":{"type":"string","minLength":1},"scope":{"enum":["call"]},"binding_id":{"type":"string","minLength":1},"kind":{"enum":["file","media","stream","card","modal","result"]}},"required":["id","scope","binding_id","kind"],"additionalProperties":false},"name":{"type":"string"},"media_type":{"type":"string"},"caption":{"type":"string"}},"required":["kind","resource_ref"],"additionalProperties":false}},"timestamp":{"type":"string"},"status":{"enum":["sent","received","updated","deleted","pending","failed"]},"role":{"enum":["user","assistant","system","tool"]}},"required":["id","room_id"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.command.send_file",
                 {Jido.Chat.Signal.SendFile, :send_file, ["room_id", "resource_ref"], :message,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"text":{"type":"string"},"sender":{"type":"object","properties":{"id":{"type":"string","minLength":1},"username":{"type":"string"},"display_name":{"type":"string"},"is_bot":{"type":"boolean"},"is_self":{"type":"boolean"}},"required":["id"],"additionalProperties":false},"thread_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"reply_to_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"media":{"type":"array","items":{"type":"object","properties":{"kind":{"enum":["image","audio","video","file"]},"resource_ref":{"type":"object","properties":{"id":{"type":"string","minLength":1},"scope":{"enum":["call"]},"binding_id":{"type":"string","minLength":1},"kind":{"enum":["file","media","stream","card","modal","result"]}},"required":["id","scope","binding_id","kind"],"additionalProperties":false},"name":{"type":"string"},"media_type":{"type":"string"},"caption":{"type":"string"}},"required":["kind","resource_ref"],"additionalProperties":false}},"timestamp":{"type":"string"},"status":{"enum":["sent","received","updated","deleted","pending","failed"]},"role":{"enum":["user","assistant","system","tool"]}},"required":["id","room_id"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.command.post_message",
                 {Jido.Chat.Signal.PostMessage, :post_message, ["room_id", "content"], :message,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"text":{"type":"string"},"sender":{"type":"object","properties":{"id":{"type":"string","minLength":1},"username":{"type":"string"},"display_name":{"type":"string"},"is_bot":{"type":"boolean"},"is_self":{"type":"boolean"}},"required":["id"],"additionalProperties":false},"thread_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"reply_to_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"media":{"type":"array","items":{"type":"object","properties":{"kind":{"enum":["image","audio","video","file"]},"resource_ref":{"type":"object","properties":{"id":{"type":"string","minLength":1},"scope":{"enum":["call"]},"binding_id":{"type":"string","minLength":1},"kind":{"enum":["file","media","stream","card","modal","result"]}},"required":["id","scope","binding_id","kind"],"additionalProperties":false},"name":{"type":"string"},"media_type":{"type":"string"},"caption":{"type":"string"}},"required":["kind","resource_ref"],"additionalProperties":false}},"timestamp":{"type":"string"},"status":{"enum":["sent","received","updated","deleted","pending","failed"]},"role":{"enum":["user","assistant","system","tool"]}},"required":["id","room_id"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.command.edit_message",
                 {Jido.Chat.Signal.EditMessage, :edit_message, ["room_id", "message_id", "text"], :message,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"text":{"type":"string"},"sender":{"type":"object","properties":{"id":{"type":"string","minLength":1},"username":{"type":"string"},"display_name":{"type":"string"},"is_bot":{"type":"boolean"},"is_self":{"type":"boolean"}},"required":["id"],"additionalProperties":false},"thread_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"reply_to_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"media":{"type":"array","items":{"type":"object","properties":{"kind":{"enum":["image","audio","video","file"]},"resource_ref":{"type":"object","properties":{"id":{"type":"string","minLength":1},"scope":{"enum":["call"]},"binding_id":{"type":"string","minLength":1},"kind":{"enum":["file","media","stream","card","modal","result"]}},"required":["id","scope","binding_id","kind"],"additionalProperties":false},"name":{"type":"string"},"media_type":{"type":"string"},"caption":{"type":"string"}},"required":["kind","resource_ref"],"additionalProperties":false}},"timestamp":{"type":"string"},"status":{"enum":["sent","received","updated","deleted","pending","failed"]},"role":{"enum":["user","assistant","system","tool"]}},"required":["id","room_id"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.command.delete_message",
                 {Jido.Chat.Signal.DeleteMessage, :delete_message, ["room_id", "message_id"], :acknowledgement,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"acknowledged":{"type":"boolean"}},"required":["acknowledged"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.command.start_typing",
                 {Jido.Chat.Signal.StartTyping, :start_typing, ["room_id"], :acknowledgement,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"acknowledged":{"type":"boolean"}},"required":["acknowledged"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.query.fetch_metadata",
                 {Jido.Chat.Signal.FetchMetadata, :fetch_metadata, ["room_id"], :conversation,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"id":{"type":"string","minLength":1},"name":{"type":"string"},"kind":{"enum":["direct","group","channel","thread","unknown"]},"topic":{"type":"string"}},"required":["id"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.query.fetch_thread",
                 {Jido.Chat.Signal.FetchThread, :fetch_thread, ["room_id"], :thread,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"parent_message_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"name":{"type":"string"},"delivery_room_ref":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]}},"required":["id","room_id"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.query.fetch_message",
                 {Jido.Chat.Signal.FetchMessage, :fetch_message, ["room_id", "message_id"], :message,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"text":{"type":"string"},"sender":{"type":"object","properties":{"id":{"type":"string","minLength":1},"username":{"type":"string"},"display_name":{"type":"string"},"is_bot":{"type":"boolean"},"is_self":{"type":"boolean"}},"required":["id"],"additionalProperties":false},"thread_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"reply_to_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"media":{"type":"array","items":{"type":"object","properties":{"kind":{"enum":["image","audio","video","file"]},"resource_ref":{"type":"object","properties":{"id":{"type":"string","minLength":1},"scope":{"enum":["call"]},"binding_id":{"type":"string","minLength":1},"kind":{"enum":["file","media","stream","card","modal","result"]}},"required":["id","scope","binding_id","kind"],"additionalProperties":false},"name":{"type":"string"},"media_type":{"type":"string"},"caption":{"type":"string"}},"required":["kind","resource_ref"],"additionalProperties":false}},"timestamp":{"type":"string"},"status":{"enum":["sent","received","updated","deleted","pending","failed"]},"role":{"enum":["user","assistant","system","tool"]}},"required":["id","room_id"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.query.get_user",
                 {Jido.Chat.Signal.GetUser, :get_user, ["user_id"], :user,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"id":{"type":"string","minLength":1},"username":{"type":"string"},"display_name":{"type":"string"},"is_bot":{"type":"boolean"},"is_self":{"type":"boolean"}},"required":["id"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.query.fetch_subject",
                 {Jido.Chat.Signal.FetchSubject, :fetch_subject, ["room_id"], :subject,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"id":{"type":"string","minLength":1},"kind":{"enum":["conversation","thread","message"]},"room_id":{"type":"string","minLength":1},"title":{"type":"string"}},"required":["id","kind","room_id"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.query.get_thread_participants",
                 {Jido.Chat.Signal.GetThreadParticipants, :get_thread_participants, ["room_id"], :participants,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"participants":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string","minLength":1},"username":{"type":"string"},"display_name":{"type":"string"},"is_bot":{"type":"boolean"},"is_self":{"type":"boolean"}},"required":["id"],"additionalProperties":false}},"complete":{"type":"boolean"},"scope":{"enum":["conversation","thread","observed"]},"next_cursor":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]}},"required":["participants","complete","scope","next_cursor"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.command.mark_as_read",
                 {Jido.Chat.Signal.MarkAsRead, :mark_as_read, ["room_id", "message_id"], :acknowledgement,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"acknowledged":{"type":"boolean"}},"required":["acknowledged"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.query.fetch_media",
                 {Jido.Chat.Signal.FetchMedia, :fetch_media, ["media_ref"], :resource,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"resource_ref":{"type":"object","properties":{"id":{"type":"string","minLength":1},"scope":{"enum":["call"]},"binding_id":{"type":"string","minLength":1},"kind":{"enum":["file","media","stream","card","modal","result"]}},"required":["id","scope","binding_id","kind"],"additionalProperties":false}},"required":["resource_ref"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.command.add_reaction",
                 {Jido.Chat.Signal.AddReaction, :add_reaction, ["room_id", "message_id", "reaction"], :acknowledgement,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"acknowledged":{"type":"boolean"}},"required":["acknowledged"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.command.remove_reaction",
                 {Jido.Chat.Signal.RemoveReaction, :remove_reaction, ["room_id", "message_id", "reaction"],
                  :acknowledgement,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"acknowledged":{"type":"boolean"}},"required":["acknowledged"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.command.post_ephemeral",
                 {Jido.Chat.Signal.PostEphemeral, :post_ephemeral, ["room_id", "user_id", "text"], :message,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"text":{"type":"string"},"sender":{"type":"object","properties":{"id":{"type":"string","minLength":1},"username":{"type":"string"},"display_name":{"type":"string"},"is_bot":{"type":"boolean"},"is_self":{"type":"boolean"}},"required":["id"],"additionalProperties":false},"thread_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"reply_to_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"media":{"type":"array","items":{"type":"object","properties":{"kind":{"enum":["image","audio","video","file"]},"resource_ref":{"type":"object","properties":{"id":{"type":"string","minLength":1},"scope":{"enum":["call"]},"binding_id":{"type":"string","minLength":1},"kind":{"enum":["file","media","stream","card","modal","result"]}},"required":["id","scope","binding_id","kind"],"additionalProperties":false},"name":{"type":"string"},"media_type":{"type":"string"},"caption":{"type":"string"}},"required":["kind","resource_ref"],"additionalProperties":false}},"timestamp":{"type":"string"},"status":{"enum":["sent","received","updated","deleted","pending","failed"]},"role":{"enum":["user","assistant","system","tool"]}},"required":["id","room_id"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.command.post_channel_message",
                 {Jido.Chat.Signal.PostChannelMessage, :post_channel_message, ["room_id", "text"], :message,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"text":{"type":"string"},"sender":{"type":"object","properties":{"id":{"type":"string","minLength":1},"username":{"type":"string"},"display_name":{"type":"string"},"is_bot":{"type":"boolean"},"is_self":{"type":"boolean"}},"required":["id"],"additionalProperties":false},"thread_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"reply_to_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"media":{"type":"array","items":{"type":"object","properties":{"kind":{"enum":["image","audio","video","file"]},"resource_ref":{"type":"object","properties":{"id":{"type":"string","minLength":1},"scope":{"enum":["call"]},"binding_id":{"type":"string","minLength":1},"kind":{"enum":["file","media","stream","card","modal","result"]}},"required":["id","scope","binding_id","kind"],"additionalProperties":false},"name":{"type":"string"},"media_type":{"type":"string"},"caption":{"type":"string"}},"required":["kind","resource_ref"],"additionalProperties":false}},"timestamp":{"type":"string"},"status":{"enum":["sent","received","updated","deleted","pending","failed"]},"role":{"enum":["user","assistant","system","tool"]}},"required":["id","room_id"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.command.stream",
                 {Jido.Chat.Signal.Stream, :stream, ["room_id", "resource_ref"], :message,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"text":{"type":"string"},"sender":{"type":"object","properties":{"id":{"type":"string","minLength":1},"username":{"type":"string"},"display_name":{"type":"string"},"is_bot":{"type":"boolean"},"is_self":{"type":"boolean"}},"required":["id"],"additionalProperties":false},"thread_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"reply_to_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"media":{"type":"array","items":{"type":"object","properties":{"kind":{"enum":["image","audio","video","file"]},"resource_ref":{"type":"object","properties":{"id":{"type":"string","minLength":1},"scope":{"enum":["call"]},"binding_id":{"type":"string","minLength":1},"kind":{"enum":["file","media","stream","card","modal","result"]}},"required":["id","scope","binding_id","kind"],"additionalProperties":false},"name":{"type":"string"},"media_type":{"type":"string"},"caption":{"type":"string"}},"required":["kind","resource_ref"],"additionalProperties":false}},"timestamp":{"type":"string"},"status":{"enum":["sent","received","updated","deleted","pending","failed"]},"role":{"enum":["user","assistant","system","tool"]}},"required":["id","room_id"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.command.open_modal",
                 {Jido.Chat.Signal.OpenModal, :open_modal, ["room_id", "modal"], :modal,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"id":{"type":"string","minLength":1},"opened":{"type":"boolean"}},"required":["opened"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.query.load_options",
                 {Jido.Chat.Signal.LoadOptions, :load_options, ["interaction_id", "query"], :options,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"options":{"type":"array","items":{"type":"object","properties":{"label":{"type":"string"},"value":{"type":"string"},"description":{"type":"string"},"url":{"type":"string"}},"required":["label","value"],"additionalProperties":false}},"option_groups":{"type":"array","items":{"type":"object","properties":{"label":{"type":"string"},"options":{"type":"array","items":{"type":"object","properties":{"label":{"type":"string"},"value":{"type":"string"},"description":{"type":"string"},"url":{"type":"string"}},"required":["label","value"],"additionalProperties":false}}},"required":["label","options"],"additionalProperties":false}},"complete":{"type":"boolean"}},"required":["options","complete"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.query.fetch_messages",
                 {Jido.Chat.Signal.FetchMessages, :fetch_messages, ["room_id"], :message_page,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"messages":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"text":{"type":"string"},"sender":{"type":"object","properties":{"id":{"type":"string","minLength":1},"username":{"type":"string"},"display_name":{"type":"string"},"is_bot":{"type":"boolean"},"is_self":{"type":"boolean"}},"required":["id"],"additionalProperties":false},"thread_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"reply_to_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"media":{"type":"array","items":{"type":"object","properties":{"kind":{"enum":["image","audio","video","file"]},"resource_ref":{"type":"object","properties":{"id":{"type":"string","minLength":1},"scope":{"enum":["call"]},"binding_id":{"type":"string","minLength":1},"kind":{"enum":["file","media","stream","card","modal","result"]}},"required":["id","scope","binding_id","kind"],"additionalProperties":false},"name":{"type":"string"},"media_type":{"type":"string"},"caption":{"type":"string"}},"required":["kind","resource_ref"],"additionalProperties":false}},"timestamp":{"type":"string"},"status":{"enum":["sent","received","updated","deleted","pending","failed"]},"role":{"enum":["user","assistant","system","tool"]}},"required":["id","room_id"],"additionalProperties":false}},"next_cursor":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"complete":{"type":"boolean"}},"required":["messages","next_cursor","complete"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.query.fetch_channel_messages",
                 {Jido.Chat.Signal.FetchChannelMessages, :fetch_channel_messages, ["room_id"], :message_page,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"messages":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"text":{"type":"string"},"sender":{"type":"object","properties":{"id":{"type":"string","minLength":1},"username":{"type":"string"},"display_name":{"type":"string"},"is_bot":{"type":"boolean"},"is_self":{"type":"boolean"}},"required":["id"],"additionalProperties":false},"thread_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"reply_to_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"media":{"type":"array","items":{"type":"object","properties":{"kind":{"enum":["image","audio","video","file"]},"resource_ref":{"type":"object","properties":{"id":{"type":"string","minLength":1},"scope":{"enum":["call"]},"binding_id":{"type":"string","minLength":1},"kind":{"enum":["file","media","stream","card","modal","result"]}},"required":["id","scope","binding_id","kind"],"additionalProperties":false},"name":{"type":"string"},"media_type":{"type":"string"},"caption":{"type":"string"}},"required":["kind","resource_ref"],"additionalProperties":false}},"timestamp":{"type":"string"},"status":{"enum":["sent","received","updated","deleted","pending","failed"]},"role":{"enum":["user","assistant","system","tool"]}},"required":["id","room_id"],"additionalProperties":false}},"next_cursor":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"complete":{"type":"boolean"}},"required":["messages","next_cursor","complete"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.query.list_threads",
                 {Jido.Chat.Signal.ListThreads, :list_threads, ["room_id"], :thread_page,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"threads":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"parent_message_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"name":{"type":"string"},"delivery_room_ref":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]}},"required":["id","room_id"],"additionalProperties":false}},"next_cursor":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"complete":{"type":"boolean"}},"required":["threads","next_cursor","complete"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.command.open_thread",
                 {Jido.Chat.Signal.OpenThread, :open_thread, ["room_id", "message_id"], :thread,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"id":{"type":"string","minLength":1},"room_id":{"type":"string","minLength":1},"parent_message_id":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]},"name":{"type":"string"},"delivery_room_ref":{"anyOf":[{"type":"string","minLength":1},{"type":"null"}]}},"required":["id","room_id"],"additionalProperties":false}|
                    )
                  )}},
                {"jido.chat.command.open_dm",
                 {Jido.Chat.Signal.OpenDm, :open_dm, ["user_id"], :conversation,
                  Zoi.from_json_schema(
                    Jason.decode!(
                      ~S|{"type":"object","properties":{"id":{"type":"string","minLength":1},"name":{"type":"string"},"kind":{"enum":["direct","group","channel","thread","unknown"]},"topic":{"type":"string"}},"required":["id"],"additionalProperties":false}|
                    )
                  )}}
              ])
  @doc false
  @spec lookup(String.t()) :: tuple() | nil
  def lookup(type), do: Map.get(@operations, type)
  @doc false
  @spec all() :: map()
  def all, do: @operations
end
