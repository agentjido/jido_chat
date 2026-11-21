defmodule Jido.Chat.Discord.ActionsContractTest do
  use Covenant.Case, component: "jido_chat_discord.actions", async: true
  @moduletag capture_log: true
  import Jido.Chat.Discord.Fixtures
  alias Jido.Chat
  alias Jido.Chat.Discord.Signal, as: D

  defmodule MixedFlow do
    use Jido.Flow, name: "discord_contract_flow"

    flow do
      step("core", action: Jido.Chat.SendMessage, params: input(:core))
      step("native", action: Jido.Chat.Discord.SendRichMessage, params: input(:native), needs: ["core"])
      output(%{core: result("core"), native: result("native")})
    end
  end

  @tag obligation: "jido_chat_discord.actions.I1"
  test "facade helpers execute their core Actions with explicit request identity" do
    observer = self()

    c =
      client(fn _, method, path, body ->
        send(observer, {:wire, method, path, body})

        response =
          cond do
            path == "/channels/202/threads" -> %{"id" => "555", "parent_id" => "202", "name" => "thread"}
            path == "/channels/202" -> %{"id" => "202", "name" => "bridge", "type" => 0}
            true -> message()
          end

        {:ok, response}
      end)

    for {function, args, operation, method, path} <- [
          {:send_text, ["202", "hello"], "send_message", :post, "/channels/202/messages"},
          {:stream_text, ["202", ["hel", "lo"]], "stream_text", :post, "/channels/202/messages"},
          {:send_file, ["202", %{"content_base64" => "Ynl0ZXM=", "filename" => "proof.bin"}], "send_file", :post,
           "/channels/202/messages"},
          {:edit_message, ["202", "101", "hello"], "edit_message", :patch, "/channels/202/messages/101"},
          {:delete_message, ["202", "101"], "delete_message", :delete, "/channels/202/messages/101"},
          {:add_reaction, ["202", "101", "ok"], "add_reaction", :put, "/channels/202/messages/101/reactions/ok/@me"},
          {:remove_reaction, ["202", "101", "ok"], "remove_reaction", :delete,
           "/channels/202/messages/101/reactions/ok/@me"},
          {:fetch_metadata, ["202"], "fetch_metadata", :get, "/channels/202"},
          {:start_typing, ["202"], "start_typing", :post, "/channels/202/typing"},
          {:create_thread, ["202", "thread"], "create_thread", :post, "/channels/202/threads"}
        ] do
      assert {:ok, signal} = apply(Chat, function, [c | args] ++ [[request_id: "facade:" <> operation]])
      assert signal.data["request_id"] == "facade:" <> operation

      assert signal.data["operation"] ==
               "jido.chat." <> if(operation == "fetch_metadata", do: "query.", else: "command.") <> operation

      assert_receive {:wire, ^method, ^path, _}
      assert {:ok, _} = Jido.Signal.Catalog.validate(Chat.catalog(c), signal)
    end

    reference = %{"client_id" => c.id, "kind" => "media", "id" => "discord://attachment/202/101/9"}

    c =
      client(fn _, :get, "/channels/202/messages/101", nil ->
        {:ok,
         %{"attachments" => [%{"id" => "9", "filename" => "proof.bin", "url" => "https://cdn.discordapp.com/test"}]}}
      end)

    adapter = fn request -> {request, Req.Response.new(status: 200, body: <<0, 255, 1>>)} end

    assert {:ok, downloaded} =
             Chat.download_file(c, reference,
               request_id: "facade:download",
               options: [adapter: Chat.Discord.TestHTTP, finch_private: [discord_test_handler: adapter]]
             )

    assert downloaded.data["request_id"] == "facade:download"
    assert downloaded.data["result"]["content_base64"] == "AP8B"
  end

  @tag obligation: "jido_chat_discord.actions.I2"
  test "a real Flow composes core and native Signal Actions in order" do
    observer = self()

    c =
      client(fn _, :post, "/channels/202/messages", body ->
        send(observer, {:sent, body["content"]})
        {:ok, message(%{"content" => body["content"]})}
      end)

    core = request(Chat.Signal.SendMessage, %{"room_id" => "202", "text" => "first"})
    native = request(Chat.Discord.Signal.SendRichMessage, %{"room_id" => "202", "text" => "second"})

    assert {:ok, result} =
             Jido.Exec.run(MixedFlow, %{core: core.data, native: native.data}, %{client: c, options: []},
               max_attempts: 1
             )

    assert_receive {:sent, "first"}
    assert_receive {:sent, "second"}
    assert result.core["result"]["text"] == "first"
    assert result.native["result"]["text"] == "second"
    assert {:ok, first} = Chat.SendMessage.reply(core, result.core, source: c.source)
    assert {:ok, second} = Chat.Discord.SendRichMessage.reply(native, result.native, source: c.source)
    assert first.extensions["jidocausationid"] == core.id
    assert second.extensions["jidocausationid"] == native.id
  end

  @tag obligation: "jido_chat_discord.actions.I3"
  test "stream and binary uploads cross the private boundary exactly once" do
    observer = self()

    stream =
      Stream.resource(
        fn ->
          send(observer, :stream_open)
          ["a", "b"]
        end,
        fn
          [] -> {:halt, []}
          [h | t] -> {[h], t}
        end,
        fn _ -> send(observer, :stream_close) end
      )

    c =
      client(fn _, :post, "/channels/202/messages", body ->
        send(observer, {:body, body})
        {:ok, message()}
      end)

    assert {:ok, _} = Chat.stream_text(c, "202", stream)
    assert_receive :stream_open
    assert_receive :stream_close
    refute_receive :stream_open, 10
    assert_receive {:body, %{"content" => "ab"}}
    assert {:ok, _} = Chat.send_file(c, "202", %{"filename" => "proof.bin", "content_base64" => "AP8B"})
    assert_receive {:body, {:multipart, _, <<0, 255, 1>>, "proof.bin"}}
    refute_receive {:body, _}, 10
  end

  @tag obligation: "jido_chat_discord.actions.I4"
  test "confirmed rate rejection is typed and does not cause an automatic second write" do
    observer = self()
    secret = Base.encode64(:crypto.strong_rand_bytes(24))

    c =
      client(
        fn _, _, _, _ ->
          send(observer, :called)
          {:error, {:rejected, :rate_limited, %{retry_after_ms: 123}}}
        end,
        token: secret
      )

    request = request(Chat.Signal.SendMessage, %{"room_id" => "202", "text" => "hello"})
    assert {:error, %Chat.Error{code: :rate_limited, signal: failed} = error} = Chat.execute(c, request)
    assert failed.data["retry_after_ms"] == 123
    assert failed.data["outcome"] == "rejected"
    assert failed.extensions["jidocausationid"] == request.id
    refute inspect(error) =~ secret
    assert_receive :called
    refute_receive :called, 20
  end

  defp cases do
    [
      {D.RespondInteraction, "respond_interaction",
       %{"room_id" => "202", "interaction_id" => "909", "response_type" => 4, "data" => %{"content" => "hello"}}},
      {D.SendRichMessage, "send_rich_message",
       %{"room_id" => "202", "text" => "hello", "embeds" => [%{"title" => "hello"}]}},
      {D.StartMessageThread, "start_message_thread", %{"room_id" => "202", "message_id" => "101", "name" => "thread"}}
    ]
  end

  @tag obligation: "jido_chat_discord.actions.I5"
  test "altered Signals are rejected before transport through both execution boundaries" do
    c = client(fn _, _, _, _ -> flunk("invalid Signal reached transport") end)

    for {definition, _, data} <- cases() do
      signal = request(definition, data)
      action = Enum.find(Jido.Chat.Discord.actions(), &(&1.signal_definition() == definition))

      for altered <- [
            %{signal | data: Map.put(signal.data, "token", "blocked")},
            %{signal | extensions: %{"traceparent" => "invalid"}}
          ] do
        assert {:error, _} = Jido.Chat.execute(c, altered)

        assert {:error, _} =
                 Jido.Chat.Discord.ActionHelpers.execute(action, altered, %{client: c, options: []}, max_attempts: 1)
      end
    end
  end

  @tag obligation: "jido_chat_discord.actions.I6"
  test "native Action completions use provider identity and causal context" do
    c = client(fn _, _, _, _ -> {:ok, message(%{"id" => "provider-701", "parent_id" => "202", "name" => "thread"})} end)

    for {definition, _, data} <- cases() do
      signal = request(definition, data)
      action = Enum.find(Jido.Chat.Discord.actions(), &(&1.signal_definition() == definition))
      private = [interaction: interaction(c, "202", "909")]
      assert {:ok, completed} = Jido.Chat.execute(c, signal, options: private)
      assert completed.extensions["jidocausationid"] == signal.id
      assert completed.extensions["traceparent"] == signal.extensions["traceparent"]
      assert completed.data["request_id"] == signal.data["request_id"]
      assert {:ok, _} = Jido.Signal.Catalog.validate(Jido.Chat.catalog(c), completed)
      assert {:ok, encoded} = Jido.Signal.Codec.serialize(completed)
      assert {:ok, ^completed} = Jido.Signal.Catalog.decode(Jido.Chat.catalog(c), encoded)
      refute Jason.encode!(Jido.Signal.Codec.to_map(completed)) =~ private[:interaction].token

      assert {:ok, %{signal: second}} =
               Jido.Chat.Discord.ActionHelpers.execute(action, signal, %{client: c, options: private}, max_attempts: 1)

      assert second.data == completed.data
    end

    for {response_type, data} <- [
          {4, %{"content" => "proof"}},
          {5, %{"flags" => 64}},
          {6, nil},
          {7, %{"content" => "proof"}},
          {9,
           %{
             "title" => "Proof",
             "custom_id" => "proof-modal",
             "components" => [
               %{
                 "type" => 1,
                 "components" => [%{"type" => 4, "custom_id" => "answer", "style" => 1, "label" => "Answer"}]
               }
             ]
           }}
        ] do
      control = interaction(client(), "202", "909")

      c =
        client(fn _, :post, path, payload ->
          assert path == "/interactions/909/#{control.token}/callback"

          assert payload ==
                   if(is_nil(data), do: %{"type" => response_type}, else: %{"type" => response_type, "data" => data})

          {:ok, nil}
        end)

      request_data = %{"room_id" => "202", "interaction_id" => "909", "response_type" => response_type}
      request_data = if is_nil(data), do: request_data, else: Map.put(request_data, "data", data)
      signal = request(D.RespondInteraction, request_data)

      assert {:ok, _} = Chat.execute(c, signal, options: [interaction: control])
    end

    control = interaction(client(), "202", "909")
    c = client(fn _, :post, _, _ -> {:error, {:rejected, :not_found, %{}}} end)
    signal = request(D.RespondInteraction, %{"room_id" => "202", "interaction_id" => "909", "response_type" => 4})

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, %Chat.Error{code: :not_found} = failure} =
                 Chat.execute(c, signal, options: [interaction: control])

        refute inspect(failure) =~ control.token
      end)

    refute log =~ control.token
  end
end
