defmodule Jido.Chat.Discord.LiveAPITest do
  use ExUnit.Case, async: false
  alias Jido.Chat
  alias Jido.Chat.Discord.LiveHelpers, as: L
  @moduletag :live
  @moduletag capture_log: true
  unless System.get_env("RUN_LIVE_DISCORD_TESTS") in ["1", "true", "TRUE", "yes", "on"] do
    @moduletag skip: "set RUN_LIVE_DISCORD_TESTS=true"
  end

  setup_all do
    L.setup_target()
  end

  test "send_message facade and Signal Action retain causal and reply identity", %{client: c, room: room} do
    root = L.message(c, room, "jido full API root")
    on_exit(fn -> L.remove_message(c, room, root["id"]) end)

    reply =
      L.execute(c, Chat.Signal.SendMessage, %{
        "room_id" => room,
        "text" => "jido full API reply",
        "reply_to_id" => root["id"]
      })

    on_exit(fn -> L.remove_message(c, room, reply["id"]) end)
    fetched = L.execute(c, Chat.Signal.FetchMessage, %{"room_id" => room, "message_id" => reply["id"]})
    assert fetched["id"] == reply["id"]
    assert fetched["room_id"] == room
    assert fetched["text"] == "jido full API reply"
    assert fetched["reply_to_id"] == root["id"]
    assert reply["id"] != root["id"]

    sent =
      L.retry(fn ->
        Chat.send_message(c, %{"request_id" => "live-map-facade", "room_id" => room, "text" => "jido map facade"})
      end)
      |> L.complete(c)

    on_exit(fn -> L.remove_message(c, room, sent["id"]) end)
    assert sent["text"] == "jido map facade"
  end

  test "edit_message and delete_message prove stored state and deletion", %{client: c, room: room} do
    sent = L.message(c, room, "jido edit before")
    on_exit(fn -> L.remove_message(c, room, sent["id"]) end)
    edited = L.retry(fn -> Chat.edit_message(c, room, sent["id"], "jido edit after") end) |> L.complete(c)
    assert edited["id"] == sent["id"]
    assert edited["status"] == "updated"

    assert L.execute(c, Chat.Signal.FetchMessage, %{"room_id" => room, "message_id" => sent["id"]})["text"] ==
             "jido edit after"

    assert %{"acknowledged" => true} = L.retry(fn -> Chat.delete_message(c, room, sent["id"]) end) |> L.complete(c)
    request = L.request(Chat.Signal.FetchMessage, c, %{"room_id" => room, "message_id" => sent["id"]})
    assert {:error, %Chat.Error{code: :not_found}} = L.retry(fn -> Chat.execute(c, request) end)
  end

  test "stream_text consumes once and stores the exact final text", %{client: c, room: room} do
    test = self()

    stream =
      Stream.resource(
        fn ->
          send(test, :stream_open)
          ["jido", " stream", " complete"]
        end,
        fn
          [] -> {:halt, []}
          [part | rest] -> {[part], rest}
        end,
        fn _ -> send(test, :stream_closed) end
      )

    sent = L.retry(fn -> Chat.stream_text(c, room, stream) end) |> L.complete(c)
    on_exit(fn -> L.remove_message(c, room, sent["id"]) end)
    assert_receive :stream_open
    assert_receive :stream_closed
    refute_receive :stream_open, 20
    assert sent["text"] == "jido stream complete"

    assert L.execute(c, Chat.Signal.FetchMessage, %{"room_id" => room, "message_id" => sent["id"]})["text"] ==
             sent["text"]
  end

  test "send_file and download_file retain exact binary bytes and stable references", %{client: c, room: room} do
    bytes = <<0, 255, 1, 2, 10, 13, 65>>
    source = %{"content_base64" => Base.encode64(bytes), "filename" => "jido-boundary.bin"}
    sent = L.retry(fn -> Chat.send_file(c, room, source, caption: "jido binary test") end) |> L.complete(c)
    on_exit(fn -> L.remove_message(c, room, sent["id"]) end)
    [media] = sent["media"]
    ref = media["resource_ref"]
    assert ref["client_id"] == c.id
    assert ref["kind"] == "media"
    assert ref["id"] =~ "discord://attachment/#{room}/#{sent["id"]}/"
    assert media["name"] == "jido-boundary.bin"
    assert sent["text"] == "jido binary test"
    downloaded = Chat.download_file(c, ref) |> L.complete(c)
    assert Base.decode64!(downloaded["content_base64"]) == bytes
  end

  test "typing, metadata, and reaction changes have provider evidence", %{client: c, room: room} do
    assert %{"acknowledged" => true} = L.retry(fn -> Chat.start_typing(c, room) end) |> L.complete(c)
    metadata = Chat.fetch_metadata(c, room) |> L.complete(c)
    assert metadata["id"] == room
    assert metadata["name"] == "bridge"
    assert metadata["kind"] == "channel"
    sent = L.message(c, room, "jido reaction state test")
    on_exit(fn -> L.remove_message(c, room, sent["id"]) end)
    assert %{"acknowledged" => true} = L.retry(fn -> Chat.add_reaction(c, room, sent["id"], "👍") end) |> L.complete(c)
    {:ok, raw} = L.wire(c, :get, "/channels/#{room}/messages/#{sent["id"]}")
    assert Enum.any?(raw["reactions"], &(&1["emoji"]["name"] == "👍" and &1["me"] and &1["count"] == 1))

    assert %{"acknowledged" => true} =
             L.retry(fn -> Chat.remove_reaction(c, room, sent["id"], "👍") end) |> L.complete(c)

    {:ok, raw} = L.wire(c, :get, "/channels/#{room}/messages/#{sent["id"]}")
    refute Enum.any?(raw["reactions"] || [], &(&1["emoji"]["name"] == "👍"))
  end

  test "fetch_messages traverses exact forward and backward pages", %{client: c, room: room} do
    messages = for index <- 1..3, do: L.message(c, room, "jido cursor #{index}")
    on_exit(fn -> Enum.each(messages, &L.remove_message(c, room, &1["id"])) end)
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

  test "threads preserve parent identity and direct Client channel operations", %{client: c, room: room} do
    thread = L.retry(fn -> Chat.create_thread(c, room, "jido-full-api-thread") end) |> L.complete(c)
    on_exit(fn -> L.remove_thread(c, thread["id"], room) end)
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
    root = L.message(c, room, "jido message thread root")
    on_exit(fn -> L.remove_message(c, room, root["id"]) end)

    native =
      L.execute(c, Chat.Discord.Signal.StartMessageThread, %{
        "room_id" => room,
        "message_id" => root["id"],
        "name" => "jido-native-message-thread"
      })

    on_exit(fn -> L.remove_thread(c, native["id"], room) end)
    assert native["parent_message_id"] == root["id"]
    assert native["room_id"] == room
  end

  test "list_threads finds a known archived thread and traverses its timestamp cursor", %{client: c, room: room} do
    thread = Chat.create_thread(c, room, "jido-archive-fixture") |> L.complete(c)
    on_exit(fn -> L.remove_thread(c, thread["id"], room) end)
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

  test "open_dm verifies the configured recipient and reports direct-delivery restrictions", %{client: c} do
    user =
      System.get_env("DISCORD_TEST_USER_ID")
      |> case do
        value when is_binary(value) and value != "" -> String.trim(value)
        _ -> "281856954903691264"
      end

    dm = L.execute(c, Chat.Signal.OpenDm, %{"user_id" => user})
    assert dm["kind"] == "direct"
    {:ok, raw} = L.wire(c, :get, "/channels/" <> dm["id"])
    assert Enum.any?(raw["recipients"], &(&1["id"] == user))

    case L.retry(fn -> Chat.send_text(c, dm["id"], "jido authorized direct-room API test") end) do
      {:ok, sent} ->
        id = sent.data["result"]["id"]
        on_exit(fn -> L.remove_message(c, dm["id"], id) end)
        assert sent.data["result"]["room_id"] == dm["id"]
        IO.puts("LIVE_DM_DELIVERY passed")

      {:error, %Chat.Error{code: :forbidden, signal: failed}} ->
        assert failed.data["outcome"] == "rejected"
        IO.puts("LIVE_DM_DELIVERY blocked: Discord forbids sending to the verified test user; OpenDm itself passed")

      {:error, error} ->
        flunk("unexpected direct delivery result: #{inspect(error)}")
    end
  end

  test "SendRichMessage stores native embeds and components", %{client: c, room: room} do
    data = %{
      "room_id" => room,
      "text" => "jido rich fixture",
      "embeds" => [%{"title" => "Jido API proof", "description" => "Exact provider payload"}],
      "components" => [
        %{
          "type" => 1,
          "components" => [%{"type" => 2, "style" => 1, "label" => "Jido proof", "custom_id" => "jido:proof"}]
        }
      ]
    }

    sent = L.execute(c, Chat.Discord.Signal.SendRichMessage, data)
    on_exit(fn -> L.remove_message(c, room, sent["id"]) end)
    {:ok, raw} = L.wire(c, :get, "/channels/#{room}/messages/#{sent["id"]}")
    assert hd(raw["embeds"])["title"] == "Jido API proof"
    assert hd(hd(raw["components"])["components"])["custom_id"] == "jido:proof"
  end
end
