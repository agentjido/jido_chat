defmodule Jido.Chat.Discord.LiveAPI do
  @moduledoc false
  import ExUnit.Assertions
  import Jido.Chat.LiveCase, only: [on_cleanup: 1]
  alias Jido.Chat
  alias Jido.Chat.Discord.LiveHelpers, as: L

  def send_reply(%{client: c, room: room, run_id: run_id}) do
    text = "**Jido live #{run_id}: rich reply**"
    root = L.message(c, room, "jido full API root")
    on_cleanup(fn -> L.remove_message(c, room, root["id"]) end)

    reply =
      L.execute(c, Chat.Signal.SendMessage, %{
        "room_id" => room,
        "text" => text,
        "format" => "markdown",
        "reply_to_id" => root["id"],
        "keyboard" => %{"rows" => [[%{"text" => "Jido reply", "value" => "jido:reply"}]]}
      })

    on_cleanup(fn -> L.remove_message(c, room, reply["id"]) end)
    fetched = L.execute(c, Chat.Signal.FetchMessage, %{"room_id" => room, "message_id" => reply["id"]})
    assert fetched["id"] == reply["id"]
    assert fetched["room_id"] == room
    assert fetched["text"] == text
    assert [%{"components" => [%{"custom_id" => "jido:reply"}]}] = L.raw_message(c, room, reply["id"])["components"]
    assert fetched["reply_to_id"] == root["id"]
    assert reply["id"] != root["id"]

    sent =
      Chat.send_message(c, %{"request_id" => "live-map-facade", "room_id" => room, "text" => "jido map facade"})
      |> L.complete(c)

    on_cleanup(fn -> L.remove_message(c, room, sent["id"]) end)
    assert sent["text"] == "jido map facade"
  end

  def edit_keyboard(%{client: c, room: room, run_id: run_id}) do
    initial = "Jido live #{run_id}: before edit"
    updated = "Jido live #{run_id}: after edit"
    keyboard = %{"rows" => [[%{"text" => "Jido proof", "value" => "jido:edit"}]]}

    sent = Chat.send_text(c, room, initial, keyboard: keyboard) |> L.complete(c) |> then(&L.track_message(c, room, &1))
    id = sent["id"]
    assert [%{"components" => [%{"custom_id" => "jido:edit"}]}] = L.raw_message(c, room, id)["components"]

    assert %{"id" => ^id, "status" => "updated", "text" => ^updated} =
             Chat.edit_message(c, room, id, updated, keyboard: %{"rows" => []}) |> L.complete(c)

    assert %{"content" => ^updated, "components" => []} = L.raw_message(c, room, id)
  end

  def delete(%{client: c, room: room}) do
    sent = L.message(c, room, "delete fixture") |> then(&L.track_message(c, room, &1))
    id = sent["id"]
    assert %{"acknowledged" => true} = Chat.delete_message(c, room, id) |> L.complete(c)
    L.forget_message(room, id)
    path = "/channels/#{room}/messages/#{id}"
    assert_receive {:discord_live_wire, :delete, ^path, {:ok, _}}

    request = L.request(Chat.Signal.FetchMessage, c, %{"room_id" => room, "message_id" => id})
    assert {:error, %Chat.Error{code: :not_found}} = Chat.execute(c, request)
    rejected(c, Chat.Signal.DeleteMessage, %{"room_id" => room, "message_id" => id}, :delete, path)
  end

  def metadata(%{client: c, room: room}) do
    metadata = L.execute(c, Chat.Signal.FetchMetadata, %{"room_id" => room})
    assert {:ok, raw} = L.wire(c, :get, "/channels/" <> room)
    assert metadata["id"] == raw["id"] and raw["id"] == room
    assert metadata["name"] == raw["name"] and metadata["name"] == "bridge"
    assert metadata["topic"] == raw["topic"]
    assert metadata["kind"] == "channel"
  end

  def typing(%{client: c, room: room}) do
    assert %{"acknowledged" => true} = L.execute(c, Chat.Signal.StartTyping, %{"room_id" => room})
    path = "/channels/#{room}/typing"
    assert_receive {:discord_live_wire, :post, ^path, {:ok, _}}
    refute_received {:discord_live_wire, :post, ^path, _}
  end

  def reactions(ctx), do: reactions(ctx, :public)

  def reactions(%{client: c, room: room}, mode) do
    sent = L.message(c, room, "reaction state") |> then(&L.track_message(c, room, &1))
    id = sent["id"]
    data = %{"room_id" => room, "message_id" => id, "reaction" => "👍"}

    assert %{"acknowledged" => true} = react(c, Jido.Chat.AddReaction, :add_reaction, data, mode)

    assert Enum.any?(
             L.raw_message(c, room, id)["reactions"],
             &(&1["emoji"]["name"] == "👍" and &1["me"] and &1["count"] == 1)
           )

    assert %{"acknowledged" => true} = react(c, Jido.Chat.RemoveReaction, :remove_reaction, data, mode)
    refute Enum.any?(L.raw_message(c, room, id)["reactions"] || [], &(&1["emoji"]["name"] == "👍"))
  end

  defp react(c, action, _, data, :native), do: L.native(c, action, data)

  defp react(c, _, operation, data, :public),
    do: apply(Chat, operation, [c, data["room_id"], data["message_id"], data["reaction"]]) |> L.complete(c)

  def reject_thread(%{client: c}) do
    rejected(
      c,
      Chat.Signal.CreateThread,
      %{"room_id" => "0", "name" => "Jido negative test"},
      :post,
      "/channels/0/threads"
    )
  end

  def reject_send(%{client: c}) do
    rejected(
      c,
      Chat.Signal.SendMessage,
      %{"room_id" => "0", "text" => "Jido negative test"},
      :post,
      "/channels/0/messages"
    )
  end

  defp rejected(c, definition, data, method, path) do
    request = L.request(definition, c, data)
    assert {:error, %Chat.Error{code: :not_found, signal: failed}} = Chat.execute(c, request)
    assert failed.type == request.type <> ".failed"
    assert failed.data["outcome"] == "rejected"
    assert failed.data["request_id"] == request.data["request_id"]
    assert failed.extensions["jidocausationid"] == request.id
    assert :ok = Chat.AdapterTestKit.Assertions.assert_json_round_trip(failed, Chat.catalog(c))
    assert_receive {:discord_live_wire, ^method, ^path, {:error, {:rejected, :not_found, _}}}
    refute_received {:discord_live_wire, ^method, ^path, _}
  end

  def paginate(%{client: c, room: room}) do
    messages =
      for index <- 1..3 do
        sent = L.message(c, room, "jido cursor #{index}")
        on_cleanup(fn -> L.remove_message(c, room, sent["id"]) end)
        sent
      end

    [first, second, third] = messages

    back =
      L.execute(c, Chat.Signal.FetchMessages, %{
        "room_id" => room,
        "limit" => 1,
        "cursor" => third["id"],
        "direction" => "backward"
      })

    assert Enum.map(back["messages"], & &1["id"]) == [second["id"]]
    assert back["next_cursor"] == second["id"]
    refute back["complete"]
    next = L.execute(c, Chat.Signal.FetchMessages, %{"room_id" => room, "limit" => 1, "cursor" => back["next_cursor"]})
    assert Enum.map(next["messages"], & &1["id"]) == [first["id"]]

    forward =
      L.execute(c, Chat.Signal.FetchMessages, %{
        "room_id" => room,
        "limit" => 1,
        "cursor" => first["id"],
        "direction" => "forward"
      })

    assert Enum.map(forward["messages"], & &1["id"]) == [second["id"]]
    assert forward["next_cursor"] == second["id"]
  end

  def thread(%{client: c, room: room}) do
    thread = Chat.create_thread(c, room, "jido-full-api-thread") |> L.complete(c)
    on_cleanup(fn -> L.remove_thread(c, thread["id"], room) end)
    assert thread["room_id"] == room
    fetched = L.execute(c, Chat.Signal.FetchThread, %{"room_id" => room, "thread_id" => thread["id"]})
    assert fetched["id"] == thread["id"]
    assert fetched["room_id"] == room
    sent = Chat.send_text(c, room, "jido thread source", thread_id: thread["id"]) |> L.complete(c)
    assert sent["room_id"] == room
    assert sent["thread_id"] == thread["id"]
    # Current core schemas use the thread channel as room_id for these calls.
    assert L.execute(c, Chat.Signal.FetchMessage, %{"room_id" => thread["id"], "message_id" => sent["id"]})["id"] ==
             sent["id"]

    Chat.edit_message(c, thread["id"], sent["id"], "jido thread edited") |> L.complete(c)
    history = L.execute(c, Chat.Signal.FetchMessages, %{"room_id" => room, "thread_id" => thread["id"], "limit" => 1})
    assert hd(history["messages"])["text"] == "jido thread edited"
    assert hd(history["messages"])["room_id"] == room
    assert hd(history["messages"])["thread_id"] == thread["id"]
    Chat.delete_message(c, thread["id"], sent["id"]) |> L.complete(c)
    thread_id = thread["id"]
    assert %{"id" => ^thread_id, "kind" => "thread"} = Chat.fetch_metadata(c, thread_id) |> L.complete(c)
    assert %{"acknowledged" => true} = Chat.start_typing(c, room, thread_id: thread_id) |> L.complete(c)
    path = "/channels/#{thread_id}/typing"
    assert_receive {:discord_live_wire, :post, ^path, {:ok, _}}
  end

  def archived_thread(%{client: c, room: room}) do
    thread = Chat.create_thread(c, room, "jido-archive-fixture") |> L.complete(c)
    on_cleanup(fn -> L.remove_thread(c, thread["id"], room) end)
    assert {:ok, archived} = L.wire(c, :patch, "/channels/" <> thread["id"], %{"archived" => true})
    assert archived["thread_metadata"]["archived"]
    page = L.execute(c, Chat.Signal.ListThreads, %{"room_id" => room, "limit" => 1})
    assert hd(page["threads"])["id"] == thread["id"]
    assert hd(page["threads"])["room_id"] == room
    assert page["next_cursor"] == archived["thread_metadata"]["archive_timestamp"] or page["complete"]

    if page["next_cursor"] do
      next = L.execute(c, Chat.Signal.ListThreads, %{"room_id" => room, "limit" => 1, "cursor" => page["next_cursor"]})
      refute Enum.any?(next["threads"], &(&1["id"] == thread["id"]))
    end
  end

  def bot_identity(%{client: c} = ctx) do
    assert {:ok, %{"id" => bot_id, "bot" => true}} = L.wire(c, :get, "/users/@me")
    assert is_binary(bot_id)
    metadata(ctx)
    typing(ctx)
  end

  def direct(%{client: c, user_id: user}) do
    dm = L.execute(c, Chat.Signal.OpenDm, %{"user_id" => user})
    assert dm["kind"] == "direct"
    assert {:ok, raw} = L.wire(c, :get, "/channels/" <> dm["id"])
    assert Enum.any?(raw["recipients"], &(&1["id"] == user))
    dm
  end

  def direct_delivery(%{client: c, run_id: run_id} = ctx) do
    dm = direct(ctx)
    text = "Jido live #{run_id}: authorized direct-room test"

    case Chat.send_text(c, dm["id"], text) do
      {:ok, signal} ->
        id = signal.data["result"]["id"]
        on_cleanup(fn -> L.remove_message(c, dm["id"], id) end)
        assert L.complete({:ok, signal}, c)["room_id"] == dm["id"]

      {:error, %Chat.Error{code: :forbidden, signal: failed}} ->
        assert failed.data["outcome"] == "rejected"
        {:blocked, "Discord forbids delivery to the configured test recipient"}

      other ->
        L.complete(other, c)
    end
  end
end
