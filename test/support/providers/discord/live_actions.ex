defmodule Jido.Chat.Discord.LiveActions do
  @moduledoc false
  import ExUnit.Assertions
  import Jido.Chat.LiveCase, only: [on_cleanup: 1]
  alias Jido.Chat
  alias Jido.Chat.Discord
  alias Jido.Chat.Discord.{LiveAPI, LiveHelpers}
  alias LiveHelpers, as: L

  def edit_delete(%{client: c, room: room, run_id: run_id}) do
    sent = send_message(c, room, "Jido live #{run_id}: native send")
    id = sent["id"]
    address = %{"message_id" => id, "room_id" => room}
    edited = "Jido live #{run_id}: native edit"

    assert %{"id" => ^id, "status" => "updated", "text" => ^edited} =
             L.native(c, Chat.EditMessage, Map.put(address, "text", edited))

    assert L.raw_message(c, room, id)["content"] == edited
    assert L.execute(c, Chat.Signal.FetchMessage, address)["text"] == edited
    assert %{"acknowledged" => true} = L.native(c, Chat.DeleteMessage, address)
    L.forget_message(room, id)
    assert {:error, %Chat.Error{code: :not_found}} = Chat.execute(c, L.request(Chat.Signal.FetchMessage, c, address))
  end

  def render_and_send(%{client: c, room: room, run_id: run_id}) do
    parts = ["Jido live #{run_id}", " finite", " render"]
    text = Chat.Adapter.render_stream(parts)
    assert text == Enum.join(parts)
    sent = send_message(c, room, text)
    id = sent["id"]
    path = "/channels/#{room}/messages"
    assert_receive {:discord_live_wire, :post, ^path, {:ok, %{"content" => ^text, "id" => ^id}}}
    refute_received {:discord_live_wire, :post, ^path, _}
  end

  def rich_and_reply(%{client: c, room: room, run_id: run_id}) do
    text = "**Jido live #{run_id}: rich message**"

    rich =
      L.native(c, Discord.SendRichMessage, %{
        "room_id" => room,
        "text" => text,
        "embeds" => [%{"title" => "Jido API proof", "description" => "Exact provider payload"}],
        "components" => [
          %{
            "type" => 1,
            "components" => [
              %{"type" => 2, "style" => 1, "label" => "Jido proof", "custom_id" => "jido:proof"}
            ]
          }
        ]
      })
      |> then(&L.track_message(c, room, &1))

    raw = L.raw_message(c, room, rich["id"])
    assert raw["content"] == text
    assert [%{"title" => "Jido API proof", "description" => "Exact provider payload"}] = raw["embeds"]
    assert [%{"components" => [%{"custom_id" => "jido:proof"}]}] = raw["components"]

    rendered = Chat.Adapter.render_stream(["Jido", " native", " reply"])
    reply = reply_to(c, room, rich["id"], rendered)
    reply_id = reply["id"]
    updated = rendered <> " edited"

    assert %{"id" => ^reply_id, "text" => ^updated} =
             L.native(c, Chat.EditMessage, %{"room_id" => room, "message_id" => reply_id, "text" => updated})

    stored = L.raw_message(c, room, reply_id)
    assert stored["content"] == updated
    assert get_in(stored, ["message_reference", "message_id"]) == rich["id"]
  end

  def reply(%{client: c, room: room, run_id: run_id}) do
    root = send_message(c, room, "Jido live #{run_id}: native reply root")
    reply_to(c, room, root["id"], "Jido live #{run_id}: native reply")
  end

  def reactions(ctx), do: LiveAPI.reactions(ctx, :native)

  def message_thread(%{client: c, room: room, run_id: run_id}) do
    root = send_message(c, room, "Jido live #{run_id}: native thread root")

    thread =
      L.native(c, Discord.StartMessageThread, %{
        "room_id" => room,
        "message_id" => root["id"],
        "name" => "Jido live #{run_id}"
      })

    thread_id = thread["id"]
    on_cleanup(fn -> L.remove_thread(c, thread_id, room) end)
    assert thread["room_id"] == room
    assert thread["parent_message_id"] == root["id"]

    text = "Jido live #{run_id}: inside native thread"
    sent = L.native(c, Chat.SendMessage, %{"room_id" => room, "thread_id" => thread_id, "text" => text})
    L.track_message(c, thread_id, sent)
    assert sent["room_id"] == room
    assert sent["thread_id"] == thread_id
    assert L.raw_message(c, thread_id, sent["id"])["content"] == text
  end

  defp send_message(c, room, text) do
    L.native(c, Chat.SendMessage, %{"room_id" => room, "text" => text}) |> then(&L.track_message(c, room, &1))
  end

  defp reply_to(c, room, root_id, text) do
    reply =
      L.native(c, Chat.SendMessage, %{"room_id" => room, "text" => text, "reply_to_id" => root_id})
      |> then(&L.track_message(c, room, &1))

    assert reply["reply_to_id"] == root_id
    assert reply["id"] != root_id

    assert %{"content" => ^text, "message_reference" => %{"message_id" => ^root_id}} =
             L.raw_message(c, room, reply["id"])

    reply
  end
end
