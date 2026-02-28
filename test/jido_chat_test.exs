defmodule Jido.ChatTest do
  use ExUnit.Case, async: true

  alias Jido.Chat

  test "facade constructors delegate to core structs" do
    room = Chat.new_room(%{type: :direct})
    participant = Chat.new_participant(%{type: :human})

    message =
      Chat.new_message(%{
        room_id: room.id,
        sender_id: participant.id,
        role: :user,
        content: [Chat.text("hello")]
      })

    assert room.type == :direct
    assert participant.type == :human
    assert message.role == :user
    assert [%Jido.Chat.Content.Text{text: "hello"}] = message.content
  end
end
