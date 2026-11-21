defmodule Jido.Chat.Discord.AdapterContractTest do
  use Covenant.Case, component: "jido_chat_discord.adapter", async: true
  @moduletag capture_log: true
  import Jido.Chat.Discord.Fixtures
  alias Jido.Chat

  @tag obligation: "jido_chat_discord.adapter.I1"
  test "public discovery and all 23 capabilities have fixed expectations" do
    expected = File.read!(Path.join(__DIR__, "../../fixtures/discord/capabilities.json")) |> Jason.decode!()
    c = client(fn _, _, _, _ -> flunk("discovery performed I/O") end)
    assert :ok = Chat.AdapterTestKit.Assertions.assert_capability_coherence(Chat.Discord.Adapter)
    assert length(Map.keys(expected)) == 23

    assert Map.new(Chat.Discord.Adapter.capabilities(), fn {k, v} -> {Atom.to_string(k), Atom.to_string(v)} end) ==
             expected

    assert Chat.Discord.adapter() == Chat.Discord.Adapter

    assert Chat.Discord.actions() == [
             Chat.Discord.RespondInteraction,
             Chat.Discord.SendRichMessage,
             Chat.Discord.StartMessageThread
           ]

    assert length(Chat.actions(c)) == 26
    assert length(Chat.operations(c)) == 26
    assert length(Chat.actions()) == 23
    assert Chat.capabilities(c) == Chat.Discord.Adapter.capabilities()
    assert Chat.event_definitions(c) == Chat.Discord.event_definitions()
    assert Chat.signal_definitions(c) == Chat.signal_definitions() ++ Chat.Discord.signal_definitions()
    assert Chat.emoji(:thumbs_up) == "👍"

    for {name, arity} <- [
          adapter: 0,
          actions: 0,
          operations: 0,
          signal_definitions: 0,
          event_definitions: 0,
          catalog: 0
        ] do
      assert function_exported?(Chat.Discord, name, arity)
    end

    assert %Jido.Signal.Catalog{} = Chat.catalog(c)
  end

  @tag obligation: "jido_chat_discord.adapter.I2"
  test "all seven unsupported core operations fail before any provider I/O" do
    c = client(fn _, _, _, _ -> flunk("unsupported operation performed I/O") end)
    assert :ok = Chat.AdapterTestKit.Assertions.assert_unsupported_operations(c)

    cases = [
      {Chat.Signal.GetUser, %{"user_id" => "404"}},
      {Chat.Signal.FetchSubject, %{"room_id" => "202"}},
      {Chat.Signal.GetThreadParticipants, %{"room_id" => "202", "thread_id" => "555"}},
      {Chat.Signal.MarkAsRead, %{"room_id" => "202", "message_id" => "101"}},
      {Chat.Signal.PostEphemeral, %{"room_id" => "202", "user_id" => "404", "text" => "hello"}},
      {Chat.Signal.OpenModal, %{"room_id" => "202", "modal" => %{"title" => "Form"}}},
      {Chat.Signal.LoadOptions,
       %{"room_id" => "202", "interaction_id" => "909", "query" => "", "action_id" => "action"}}
    ]

    for {definition, data} <- cases do
      signal = request(definition, data)
      assert {:error, %Chat.Error{code: :unsupported, signal: failed}} = Chat.execute(c, signal)
      assert failed.type == signal.type <> ".failed"
      assert failed.data["outcome"] == "not_attempted"
      assert failed.extensions["jidocausationid"] == signal.id
      assert {:ok, _} = Jido.Signal.Catalog.validate(Chat.catalog(c), failed)
    end
  end

  @tag obligation: "jido_chat_discord.adapter.I3"
  test "same core Action keeps clients provider IDs and trace context separate" do
    for {id, provider} <- [{"discord-a", "provider-a"}, {"discord-b", "provider-b"}] do
      token = Base.encode64(:crypto.strong_rand_bytes(16))

      c =
        client(
          fn actual, :post, "/channels/202/messages", %{"content" => "hello"} ->
            assert actual == token
            {:ok, message(%{"id" => provider})}
          end,
          id: id,
          token: token
        )

      s =
        Jido.Chat.Signal.Policy.new!(
          Chat.Signal.SendMessage,
          %{"client_id" => id, "request_id" => "fixed-request", "room_id" => "202", "text" => "hello"},
          extensions: %{
            "traceparent" => "00-11111111111111111111111111111111-2222222222222222-01",
            "tracestate" => "discord=contract"
          }
        )

      assert {:ok, completed} = Chat.execute(c, s)
      assert completed.source == c.source
      assert completed.subject == Chat.Signal.Identity.conversation_subject(id, "202")
      assert completed.data["result"]["id"] == provider
      assert completed.data["request_id"] == "fixed-request"
      assert completed.extensions == Map.put(s.extensions, "jidocausationid", s.id)
      refute Jason.encode!(Jido.Signal.Codec.to_map(completed)) =~ token
    end
  end

  @tag obligation: "jido_chat_discord.adapter.I4"
  test "fixed route fixtures verify requests and provider identities" do
    for {definition, data, method, path, body, response, expected} <- [
          {Chat.Signal.SendMessage, %{"room_id" => "202", "text" => "hello", "reply_to_id" => "90"}, :post,
           "/channels/202/messages",
           %{
             "content" => "hello",
             "allowed_mentions" => %{"parse" => []},
             "message_reference" => %{"message_id" => "90"}
           }, message(), %{"id" => "101", "room_id" => "202", "status" => "sent"}},
          {Chat.Signal.EditMessage, %{"room_id" => "202", "message_id" => "101", "text" => "hello"}, :patch,
           "/channels/202/messages/101", %{"content" => "hello", "allowed_mentions" => %{"parse" => []}}, message(),
           %{"id" => "101", "status" => "updated"}},
          {Chat.Signal.DeleteMessage, %{"room_id" => "202", "message_id" => "101"}, :delete,
           "/channels/202/messages/101", nil, nil, %{"acknowledged" => true}},
          {Chat.Signal.StartTyping, %{"room_id" => "202"}, :post, "/channels/202/typing", nil, nil,
           %{"acknowledged" => true}},
          {Chat.Signal.OpenDm, %{"user_id" => "404"}, :post, "/users/@me/channels", %{"recipient_id" => "404"},
           %{"id" => "505"}, %{"id" => "505", "kind" => "direct"}},
          {Chat.Signal.FetchMetadata, %{"room_id" => "202"}, :get, "/channels/202", nil,
           %{"id" => "202", "name" => "bridge", "type" => 0},
           %{"id" => "202", "name" => "bridge", "kind" => "channel"}},
          {Chat.Signal.FetchMessage, %{"room_id" => "202", "message_id" => "101"}, :get, "/channels/202/messages/101",
           nil, message(), %{"id" => "101", "text" => "hello", "status" => "received"}},
          {Chat.Signal.FetchThread, %{"room_id" => "202", "thread_id" => "555"}, :get, "/channels/555", nil,
           %{"id" => "555", "parent_id" => "202", "name" => "thread"},
           %{"id" => "555", "room_id" => "202", "delivery_room_ref" => "555"}},
          {Chat.Signal.CreateThread, %{"room_id" => "202", "name" => "thread"}, :post, "/channels/202/threads",
           %{"name" => "thread", "auto_archive_duration" => 1440, "type" => 11},
           %{"id" => "555", "parent_id" => "202", "name" => "thread"}, %{"id" => "555", "room_id" => "202"}},
          {Chat.Signal.AddReaction, %{"room_id" => "202", "message_id" => "101", "reaction" => "ok:3"}, :put,
           "/channels/202/messages/101/reactions/ok%3A3/@me", nil, nil, %{"acknowledged" => true}},
          {Chat.Signal.RemoveReaction, %{"room_id" => "202", "message_id" => "101", "reaction" => "ok:3"}, :delete,
           "/channels/202/messages/101/reactions/ok%3A3/@me", nil, nil, %{"acknowledged" => true}},
          {Chat.Signal.FetchMessages, %{"room_id" => "202", "limit" => 1, "cursor" => "102"}, :get,
           "/channels/202/messages?before=102&limit=1", nil, [message()],
           %{"complete" => false, "next_cursor" => "101"}},
          {Chat.Signal.ListThreads, %{"room_id" => "202", "limit" => 1}, :get,
           "/channels/202/threads/archived/public?limit=2", nil,
           %{
             "threads" => [
               %{
                 "id" => "555",
                 "parent_id" => "202",
                 "thread_metadata" => %{"archive_timestamp" => "2026-01-01T00:00:00Z"}
               },
               %{"id" => "554", "parent_id" => "202"}
             ],
             "has_more" => false
           }, %{"complete" => false, "next_cursor" => "2026-01-01T00:00:00Z"}}
        ] do
      observer = self()

      c =
        client(fn _, m, p, b ->
          send(observer, {:wire, m, p, b})
          {:ok, response}
        end)

      assert {:ok, completed} = Chat.execute(c, request(definition, data))
      assert_receive {:wire, ^method, ^path, ^body}
      assert Map.take(completed.data["result"], Map.keys(expected)) == expected
    end
  end
end
