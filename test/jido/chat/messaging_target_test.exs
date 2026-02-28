defmodule Jido.Chat.MessagingTargetTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.MessagingTarget

  test "from_context/1 infers kind and captures reply ids" do
    ctx = %{
      external_room_id: 123,
      external_message_id: 456,
      external_thread_id: "thread_1",
      instance_id: "inst_1",
      channel_type: :telegram,
      chat_type: :direct
    }

    target = MessagingTarget.from_context(ctx)

    assert target.kind == :dm
    assert target.external_id == "123"
    assert target.reply_to_id == "456"
    assert target.thread_id == "thread_1"
    assert target.instance_id == "inst_1"
    assert target.channel_type == :telegram
  end

  test "for_reply/2 applies reply mode" do
    target =
      MessagingTarget.for_reply(%{external_room_id: "abc", external_message_id: "m1"}, :thread)

    assert target.reply_to_mode == :thread
    assert target.reply_to_id == "m1"
  end

  test "for_room/2 and for_thread/3 constructors" do
    room_target = MessagingTarget.for_room("room_1", kind: :dm, thread_id: "t1")

    thread_target =
      MessagingTarget.for_thread("room_1", "t2", reply_to_id: "m2", reply_to_mode: :inline)

    assert room_target.kind == :dm
    assert room_target.thread_id == "t1"
    assert thread_target.kind == :thread
    assert thread_target.thread_id == "t2"
    assert thread_target.reply_to_mode == :inline
  end

  test "to_send_opts/1 emits only applicable options" do
    target = MessagingTarget.for_thread("room_1", "t2", reply_to_id: "m2", reply_to_mode: :inline)

    opts = MessagingTarget.to_send_opts(target)
    assert Keyword.get(opts, :reply_to_id) == "m2"
    assert Keyword.get(opts, :thread_id) == "t2"
    assert Keyword.get(opts, :reply_mode) == :inline
    assert MessagingTarget.to_send_opts(MessagingTarget.for_room("room_1")) == []
  end
end
