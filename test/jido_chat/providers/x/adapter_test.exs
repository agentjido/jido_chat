defmodule Jido.Chat.X.AdapterTest do
  use Jido.Chat.AdapterTestKit, adapter: Jido.Chat.X.Adapter

  alias Jido.Chat.Client
  alias Jido.Chat.Signal.{FetchMessage, FetchMessages, Policy}
  alias Jido.Chat.X
  alias Jido.Chat.X.{Adapter, Operations}

  defmodule FakeTransport do
    @behaviour Jido.Chat.X.Transport

    @impl true
    def send_dm(participant_id, text, opts) do
      observe(opts, {:send_dm, participant_id, text})
      send(self(), {:send_dm, participant_id, text})
      {:ok, %{"data" => %{"dm_event_id" => "m1", "dm_conversation_id" => "c1", "text" => text}}}
    end

    @impl true
    def send_conversation_message(conversation_id, text, opts) do
      observe(opts, {:send_conversation_message, conversation_id, text})
      send(self(), {:send_conversation_message, conversation_id, text})

      {:ok,
       %{
         "data" => %{
           "dm_event_id" => "m2",
           "dm_conversation_id" => conversation_id,
           "text" => text
         }
       }}
    end

    @impl true
    def delete_dm_event(id, opts) do
      observe(opts, {:delete, id})
      send(self(), {:delete, id})
      :ok
    end

    @impl true
    def fetch_dm_event(id, opts) do
      observe(opts, {:fetch, id})

      case opts[:provider_result] do
        :invalid ->
          {:ok, :invalid}

        :missing_id ->
          {:ok, %{"data" => %{}}}

        :atom_keys ->
          {:ok, %{data: %{id: id, sender_id: "u1", text: "hello", created_at: 1_777_237_605_160}}}

        _ ->
          {:ok, %{"data" => event(id)}}
      end
    end

    @impl true
    def fetch_conversation_messages(id, opts) do
      observe(opts, {:fetch_messages, id})

      case opts[:provider_result] do
        :invalid -> {:ok, :invalid}
        :mixed -> {:ok, %{"data" => [event("m1"), :invalid]}}
        :complete -> {:ok, %{"data" => [event("m1")], "meta" => %{}}}
        _ -> {:ok, %{"data" => [event("m1"), event("m2")], "meta" => %{"next_token" => "next"}}}
      end
    end

    defp observe(opts, event) do
      if observer = opts[:observer], do: send(observer, {:x_transport, event, opts})
    end

    defp event(id),
      do: %{
        "id" => id,
        "sender_id" => "u1",
        "text" => "hello",
        "dm_conversation_id" => "c1",
        "created_at" => "2026-01-01T00:00:00Z"
      }
  end

  setup do
    client = Client.new!(Adapter, id: "x-test", transport: FakeTransport)
    %{client: client}
  end

  test "executes the native message lifecycle through public Chat Actions", %{client: client} do
    assert {:ok, sent} = Jido.Chat.send_text(client, "u1", "hello")
    assert sent.data["result"]["id"] == "m1"

    assert {:ok, conversation_sent} =
             Jido.Chat.send_text(client, "conversation:c1", "hello again")

    assert conversation_sent.data["result"]["id"] == "m2"

    assert {:ok, request} =
             Policy.new(FetchMessages, %{
               "client_id" => client.id,
               "request_id" => "x:history",
               "room_id" => "conversation:c1"
             })

    assert {:ok, page} = Jido.Chat.execute(client, request)
    assert Enum.map(page.data["result"]["messages"], & &1["id"]) == ["m1", "m2"]
    assert page.data["result"]["next_cursor"] == "next"

    assert {:ok, deleted} = Jido.Chat.delete_message(client, "conversation:c1", "m1")
    assert deleted.data["result"] == %{"acknowledged" => true}
  end

  test "keeps adapter config local and allows per-call overrides", %{client: client} do
    client = %{client | config: [observer: self(), marker: :config]}
    request = %{data: %{"room_id" => "u1", "text" => "hello"}}

    assert {:ok, _message} =
             Operations.invoke(:send_message, client, request, marker: :call, transient: true)

    assert_receive {:x_transport, {:send_dm, "u1", "hello"}, opts}
    assert opts[:marker] == :call
    assert opts[:transient]
    refute Keyword.has_key?(opts, :credentials)
  end

  test "fetches complete and partial direct message pages", %{client: client} do
    request =
      Policy.new!(FetchMessages, %{
        "client_id" => client.id,
        "request_id" => "x:history",
        "room_id" => "conversation:c1"
      })

    client = %{client | config: [observer: self()]}
    assert {:ok, page} = Jido.Chat.execute(client, request)
    refute page.data["result"]["complete"]
    assert page.data["result"]["next_cursor"] == "next"
    assert_receive {:x_transport, {:fetch_messages, "c1"}, opts}
    assert opts[:limit] == nil
    assert opts[:cursor] == nil

    complete_client = %{client | config: [provider_result: :complete]}
    assert {:ok, complete} = Jido.Chat.execute(complete_client, request)
    assert complete.data["result"]["complete"]
    assert complete.data["result"]["next_cursor"] == nil
  end

  test "fetches one message through a typed request", %{client: client} do
    request =
      Policy.new!(FetchMessage, %{
        "client_id" => client.id,
        "request_id" => "x:fetch",
        "room_id" => "conversation:c1",
        "message_id" => "m1"
      })

    assert {:ok, result} = Jido.Chat.execute(client, request)
    assert result.data["result"]["id"] == "m1"
    assert result.data["result"]["room_id"] == "conversation:c1"
  end

  test "normalizes direct message events with stable identities", %{client: client} do
    payload = %{"direct_message_events" => [dm_event("m1", "hello")]}

    assert {:ok, first} = Jido.Chat.normalize(client, payload)
    assert {:ok, second} = Jido.Chat.normalize(client, payload)
    assert [signal] = first.signals
    assert signal.type == "jido.chat.message.received"
    assert signal.data["room_id"] == "conversation:c1"
    assert first.id == second.id
    assert signal.data["item_id"] == hd(second.signals).data["item_id"]
  end

  test "keeps batch order and reports invalid and unsupported items", %{client: client} do
    valid = dm_event("m1", "first")
    invalid = put_in(dm_event("m2", "second")["message_create"]["sender_id"], nil)
    unsupported = %{"type" => "users_destroy", "id" => "u1"}

    assert {:ok, delivery} = Jido.Chat.normalize(client, [valid, invalid, unsupported, :bad])
    assert [received, invalid_item, unsupported_item, non_map] = delivery.signals
    assert received.data["text"] == "first"
    assert invalid_item.data["code"] == "invalid_item"
    assert invalid_item.data["item_index"] == 1
    assert unsupported_item.data["code"] == "unsupported_item"
    assert unsupported_item.data["item_index"] == 2
    assert non_map.data["code"] == "invalid_item"
    assert non_map.data["item_index"] == 3
  end

  test "normalizes supported X envelope shapes", %{client: client} do
    event = dm_event("m1", "hello")

    for payload <- [
          %{"dm_events" => [event]},
          %{"data" => [event]},
          %{"dm_event" => event}
        ] do
      assert {:ok, delivery} = Jido.Chat.normalize(client, payload)
      assert [%{data: %{"message_id" => "m1"}}] = delivery.signals
    end

    assert {:error, _} = Jido.Chat.normalize(client, :invalid)
  end

  test "retains unsupported provider events as normalization failures", %{client: client} do
    assert {:ok, delivery} = Jido.Chat.normalize(client, %{"type" => "unknown", "id" => "e1"})
    assert [failed] = delivery.signals
    assert failed.type == "jido.chat.normalization.failed"
    assert failed.data["code"] == "unsupported_item"
  end

  test "rejects invalid provider results", %{client: client} do
    fetch = %{data: %{"room_id" => "conversation:c1", "message_id" => "m1"}}

    for provider_result <- [:invalid, :missing_id] do
      assert {:error, :invalid_provider_result} =
               Operations.invoke(
                 :fetch_message,
                 %{client | config: [provider_result: provider_result]},
                 fetch,
                 []
               )
    end

    assert {:ok, atom_message} =
             Operations.invoke(
               :fetch_message,
               %{client | config: [provider_result: :atom_keys]},
               fetch,
               []
             )

    assert atom_message["id"] == "m1"

    page = %{data: %{"room_id" => "conversation:c1", "limit" => 10, "cursor" => nil}}

    for provider_result <- [:invalid, :mixed] do
      assert {:error, :invalid_provider_result} =
               Operations.invoke(
                 :fetch_messages,
                 %{client | config: [provider_result: provider_result]},
                 page,
                 []
               )
    end
  end

  test "exposes current package and unsupported boundaries", %{client: client} do
    assert X.adapter() == Adapter
    assert X.operations() == []

    assert X.event_definitions() == [
             Jido.Chat.Signal.MessageReceived,
             Jido.Chat.Signal.NormalizationFailed
           ]

    assert Adapter.default_transport() == Jido.Chat.X.Transport.XdkClient

    assert {:error, {:not_attempted, :unsupported}} =
             Adapter.invoke(client, %{type: "unknown"}, [])

    assert {:error, {:not_attempted, :unsupported}} =
             Operations.invoke(:unknown, client, %{data: %{}}, [])

    assert {:error, {:not_attempted, :unsupported}} =
             Operations.invoke(:send_message, :invalid_client, %{data: %{}}, [])

    assert {:ok, %{"id" => "u1", "kind" => "direct"}} =
             Operations.invoke(:open_dm, client, %{data: %{"user_id" => "u1"}}, [])
  end

  test "canonicalizes nested provider values for stable failure identity", %{client: client} do
    payload = %{type: "unknown", nested: [%URI{scheme: "https", host: "example.test"}]}

    assert {:ok, first} = Jido.Chat.normalize(client, payload)
    assert {:ok, second} = Jido.Chat.normalize(client, payload)
    assert first.id == second.id
    assert [failed] = first.signals
    assert failed.data["code"] == "unsupported_item"
  end

  defp dm_event(id, text) do
    %{
      "type" => "message_create",
      "id" => id,
      "created_timestamp" => 1_777_237_605_160,
      "dm_conversation_id" => "c1",
      "message_create" => %{
        "sender_id" => "u1",
        "message_data" => %{"text" => text}
      }
    }
  end
end
