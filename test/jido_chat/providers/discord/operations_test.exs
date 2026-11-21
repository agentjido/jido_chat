defmodule Jido.Chat.Discord.OperationsTest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true
  import Jido.Chat.Discord.Fixtures
  alias Jido.Chat.Discord.{Adapter, Operations}

  test "private adapter config reaches transport without credentials" do
    c =
      client(fn _, _, _, _ -> {:ok, message()} end,
        config: [transport_observer: self(), marker: :kept]
      )

    assert {:ok, _} = Jido.Chat.send_text(c, "202", "hello")
    assert_receive {:discord_transport_options, options}
    assert options[:marker] == :kept
    assert is_function(options[:handler], 4)
    refute Keyword.has_key?(options, :token)
    refute Keyword.has_key?(options, :credentials)
  end

  test "public send, edit, delete, stream, and reply APIs use canonical Signals" do
    test = self()

    c =
      client(fn token, method, path, body ->
        assert token == "test-secret"
        send(test, {method, path, body})
        {:ok, message(%{"content" => body && body["content"]})}
      end)

    assert {:ok, result} = Jido.Chat.send_text(c, "202", "hello", reply_to_id: "90")
    assert result.data["result"]["id"] == "101"

    assert_receive {:post, "/channels/202/messages",
                    %{"content" => "hello", "message_reference" => %{"message_id" => "90"}}}

    assert {:ok, _} = Jido.Chat.edit_message(c, "202", "101", "edited")
    assert_receive {:patch, "/channels/202/messages/101", %{"content" => "edited"}}
    assert {:ok, _} = Jido.Chat.delete_message(c, "202", "101")
    assert_receive {:delete, "/channels/202/messages/101", nil}
    assert {:ok, _} = Jido.Chat.stream_text(c, "202", ["a", "b"], thread_id: "thread")
    assert_receive {:post, "/channels/thread/messages", %{"content" => "ab"}}
  end

  test "acknowledgements, reactions and DM requests map to the Discord API" do
    test = self()

    c =
      client(fn _, method, path, body ->
        send(test, {method, path, body})
        {:ok, %{"id" => "dm"}}
      end)

    for {definition, data, method, path} <- [
          {Jido.Chat.Signal.StartTyping, %{"room_id" => "202"}, :post, "/channels/202/typing"},
          {Jido.Chat.Signal.AddReaction, %{"room_id" => "202", "message_id" => "101", "reaction" => "👍"}, :put,
           "/channels/202/messages/101/reactions/%F0%9F%91%8D/@me"},
          {Jido.Chat.Signal.RemoveReaction, %{"room_id" => "202", "message_id" => "101", "reaction" => "ok:3"}, :delete,
           "/channels/202/messages/101/reactions/ok%3A3/@me"},
          {Jido.Chat.Signal.OpenDm, %{"user_id" => "404"}, :post, "/users/@me/channels"}
        ] do
      assert {:ok, _} = Jido.Chat.execute(c, request(definition, data))
      assert_receive {^method, ^path, _}
    end
  end

  test "conversation and thread results use core result schemas" do
    for {type, kind} <- [{1, "direct"}, {3, "group"}, {11, "thread"}, {0, "channel"}] do
      c = client(fn _, :get, "/channels/202", nil -> {:ok, %{"id" => "202", "name" => "name", "type" => type}} end)
      assert {:ok, result} = Jido.Chat.execute(c, request(Jido.Chat.Signal.FetchMetadata, %{"room_id" => "202"}))
      assert result.data["result"]["kind"] == kind
    end

    c =
      client(fn _, method, path, _ ->
        assert {method, path} in [{:post, "/channels/202/threads"}, {:get, "/channels/555"}]
        {:ok, %{"id" => "555", "parent_id" => "202", "name" => "thread"}}
      end)

    assert {:ok, _} =
             Jido.Chat.execute(c, request(Jido.Chat.Signal.CreateThread, %{"room_id" => "202", "name" => "thread"}))

    assert {:ok, _} =
             Jido.Chat.execute(c, request(Jido.Chat.Signal.FetchThread, %{"room_id" => "202", "thread_id" => "555"}))
  end

  test "message and archived thread pages carry a usable cursor" do
    for complete <- [true, false] do
      c =
        client(fn _, :get, path, nil ->
          if String.contains?(path, "archived") do
            {:ok,
             %{
               "threads" => [
                 %{"id" => "555", "name" => "thread", "thread_metadata" => %{"archive_timestamp" => "cursor"}}
               ],
               "has_more" => not complete
             }}
          else
            {:ok, if(complete, do: [], else: [message()])}
          end
        end)

      assert {:ok, result} =
               Jido.Chat.execute(
                 c,
                 request(Jido.Chat.Signal.FetchMessages, %{"room_id" => "202", "limit" => 1, "cursor" => "99"})
               )

      assert result.data["result"]["complete"] == complete
      assert result.data["result"]["next_cursor"] == if(complete, do: nil, else: "101")

      assert {:ok, result} =
               Jido.Chat.execute(c, request(Jido.Chat.Signal.ListThreads, %{"room_id" => "202", "limit" => 1}))

      assert result.data["result"]["complete"] == complete
      assert result.data["result"]["next_cursor"] == if(complete, do: nil, else: "cursor")
    end
  end

  test "query messages validate provider results" do
    c = client(fn _, _, _, _ -> {:ok, message()} end)

    assert {:ok, result} =
             Jido.Chat.execute(c, request(Jido.Chat.Signal.FetchMessage, %{"room_id" => "202", "message_id" => "101"}))

    assert result.data["result"]["text"] == "hello"
    c = client(fn _, _, _, _ -> {:ok, [%{}]} end)
    assert {:error, _} = Jido.Chat.execute(c, request(Jido.Chat.Signal.FetchMessages, %{"room_id" => "202"}))
  end

  test "files use inline bytes or explicit file references" do
    test = self()

    c =
      client(fn _, :post, "/channels/202/messages", {:multipart, payload, bytes, filename} ->
        send(test, {:uploaded, payload, bytes, filename})
        {:ok, message(%{"attachments" => [%{"id" => "9", "filename" => filename}]})}
      end)

    data = %{
      "room_id" => "202",
      "caption" => "file",
      "source" => %{"content_base64" => Base.encode64("bytes"), "filename" => "test.txt"}
    }

    assert {:ok, _} = Jido.Chat.execute(c, request(Jido.Chat.Signal.SendFile, data))
    assert_receive {:uploaded, %{"content" => "file"}, "bytes", "test.txt"}
    path = Path.join(System.tmp_dir!(), "discord-upload-#{System.unique_integer([:positive])}.txt")
    File.write!(path, "local")
    on_exit(fn -> File.rm(path) end)
    source = %{"client_id" => c.id, "kind" => "file", "id" => path}
    assert {:ok, _} = Jido.Chat.execute(c, request(Jido.Chat.Signal.SendFile, Map.put(data, "source", source)))
    assert_receive {:uploaded, _, "local", _}
  end

  test "media download refreshes its private signed URL from Discord" do
    c =
      client(fn _, :get, "/channels/202/messages/101", nil ->
        {:ok,
         %{"attachments" => [%{"id" => "9", "filename" => "file.txt", "url" => "https://cdn.discordapp.com/test"}]}}
      end)

    ref = %{"client_id" => c.id, "kind" => "media", "id" => "discord://attachment/202/101/9"}
    adapter = fn req -> {req, Req.Response.new(status: 200, body: "bytes")} end

    assert {:ok, result} =
             Jido.Chat.execute(c, request(Jido.Chat.Signal.DownloadFile, %{"resource_ref" => ref}),
               options: [adapter: Jido.Chat.Discord.TestHTTP, finch_private: [discord_test_handler: adapter]]
             )

    assert result.data["result"]["content_base64"] == Base.encode64("bytes")

    assert {:error, _} =
             Jido.Chat.execute(
               c,
               request(Jido.Chat.Signal.DownloadFile, %{
                 "resource_ref" => Map.put(ref, "id", "discord://attachment/missing")
               }),
               options: [adapter: Jido.Chat.Discord.TestHTTP, finch_private: [discord_test_handler: adapter]]
             )
  end

  test "native interaction responses use private execution credentials" do
    test = self()

    c =
      client(fn _, :post, path, body ->
        send(test, {path, body})
        {:ok, ""}
      end)

    s =
      request(Jido.Chat.Discord.Signal.RespondInteraction, %{
        "room_id" => "202",
        "interaction_id" => "123",
        "response_type" => 9,
        "data" => %{"title" => "modal"}
      })

    private = interaction(c, "202", "123")
    assert {:ok, result} = Jido.Chat.execute(c, s, options: [interaction: private])
    assert result.data["result"] == %{"acknowledged" => true}
    path = "/interactions/123/#{private.token}/callback"
    assert_receive {^path, %{"type" => 9}}
    refute Jason.encode!(Jido.Signal.Codec.to_map(result)) =~ private.token
    assert {:error, _} = Jido.Chat.execute(c, s)
  end

  test "missing credentials, unsupported operations, and provider rejection stay safe" do
    c = client()
    s = request(Jido.Chat.Signal.SendMessage, %{"room_id" => "202", "text" => "hello"})
    assert {:error, {:not_attempted, :missing_token}} = Operations.invoke(:send_message, %{c | credentials: %{}}, s, [])
    assert {:error, {:not_attempted, :unsupported}} = Adapter.invoke(c, %{s | type: "unknown"}, [])
    assert {:error, {:not_attempted, :unsupported}} = Operations.invoke(:unknown, c, s, [])
    c = client(fn _, _, _, _ -> {:error, {:rejected, :forbidden}} end)
    assert {:error, error} = Jido.Chat.execute(c, s)
    refute inspect(error) =~ "test-secret"
  end

  test "thread sends keep the parent room and the delivery channel" do
    c = client(fn _, :post, "/channels/thread/messages", _ -> {:ok, message(%{"channel_id" => "thread"})} end)
    assert {:ok, result} = Jido.Chat.send_text(c, "202", "hello", thread_id: "thread")
    assert result.data["result"]["room_id"] == "202"
    assert result.data["result"]["thread_id"] == "thread"
  end

  test "unsupported formatting and archive direction fail before I/O" do
    c = client(fn _, _, _, _ -> flunk("unexpected I/O") end)
    assert {:error, _} = Jido.Chat.send_text(c, "202", "<b>hi</b>", format: :html)
    s = request(Jido.Chat.Signal.ListThreads, %{"room_id" => "202", "direction" => "forward"})
    assert {:error, _} = Jido.Chat.execute(c, s)
  end

  test "invalid attachment references and failed CDN downloads stay private" do
    for {attachments, status} <- [
          {[], 200},
          {[%{"id" => "9", "url" => "http://localhost/private"}], 200},
          {[%{"id" => "9", "url" => "https://cdn.discordapp.com/private"}], 404}
        ] do
      c = client(fn _, _, _, _ -> {:ok, %{"attachments" => attachments}} end)
      ref = %{"client_id" => c.id, "kind" => "media", "id" => "discord://attachment/202/101/9"}
      adapter = fn req -> {req, Req.Response.new(status: status, body: "private")} end

      assert {:error, error} =
               Jido.Chat.download_file(c, ref,
                 options: [adapter: Jido.Chat.Discord.TestHTTP, finch_private: [discord_test_handler: adapter]]
               )

      refute inspect(error) =~ "private"
    end

    ref = %{"client_id" => "discord-test", "kind" => "url", "id" => "https://example.com/file"}
    assert {:error, _} = Jido.Chat.download_file(client(), ref)
  end
end
