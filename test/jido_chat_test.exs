defmodule Jido.ChatTest do
  use ExUnit.Case, async: true

  alias Jido.Chat

  test "facade constructors delegate to core structs" do
    room = Chat.new_room(%{type: :direct})
    participant = Chat.new_participant(%{type: :human})

    message =
      Chat.message(%{
        external_room_id: room.id,
        external_message_id: "m1",
        text: "hello"
      })

    assert room.type == :direct
    assert participant.type == :human
    assert message.text == "hello"
    assert message.external_room_id == room.id
  end
end
