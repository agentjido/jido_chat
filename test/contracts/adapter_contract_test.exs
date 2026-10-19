defmodule Jido.Chat.AdapterContractTest do
  use Covenant.Case, component: "jido_chat.adapter", async: true
  @moduletag capture_log: true
  alias Jido.Chat
  alias Jido.Chat.ContractFixtures, as: F

  defmodule BadStatus do
    use Jido.Chat.Adapter
    def capabilities, do: %{send_message: :fallback}
    def invoke(_, _, _), do: raise("must not run")
    def normalize(_, _, _), do: raise("must not run")
  end

  defmodule DuplicateOperation do
    use Jido.Chat.Adapter
    def capabilities, do: %{}
    def operations, do: [{Jido.Chat.Signal.SendMessage, Jido.Chat.SendMessage}]
    def invoke(_, _, _), do: raise("must not run")
    def normalize(_, _, _), do: raise("must not run")
  end

  defmodule WrongPair do
    use Jido.Chat.Adapter
    def capabilities, do: %{}
    def operations, do: [{Jido.Chat.Signal.SendMessage, Jido.Chat.ContractFixtures.ProviderAction}]
    def invoke(_, _, _), do: raise("must not run")
    def normalize(_, _, _), do: raise("must not run")
  end

  defmodule WrongEvent do
    use Jido.Chat.Adapter
    def capabilities, do: %{}
    def event_definitions, do: [Jido.Chat.Signal.SendMessage]
    def invoke(_, _, _), do: raise("must not run")
    def normalize(_, _, _), do: raise("must not run")
  end

  @tag obligation: "jido_chat.adapter.I1"
  test "the adapter behaviour has explicit required and optional callbacks and support statuses" do
    assert Enum.sort(Chat.Adapter.behaviour_info(:callbacks)) ==
             Enum.sort(
               channel_type: 0,
               capabilities: 0,
               default_transport: 0,
               invoke: 3,
               normalize: 3,
               operations: 0,
               event_definitions: 0
             )

    assert Enum.sort(Chat.Adapter.behaviour_info(:optional_callbacks)) ==
             Enum.sort(default_transport: 0, operations: 0, event_definitions: 0)

    assert Chat.Adapter.operations(F.FirstAdapter) == []
    assert Chat.Adapter.event_definitions(F.FirstAdapter) == Chat.event_definitions()

    client = F.client(F.ExtendedAdapter)
    matrix = Chat.capabilities(client)
    assert matrix[:send_message] == :native
    assert map_size(matrix) == 23
    assert Enum.all?(Map.delete(matrix, :send_message), fn {_, status} -> status == :unsupported end)

    for adapter <- [BadStatus, DuplicateOperation, WrongPair, WrongEvent, UnknownContractAdapter] do
      assert {:error, %Chat.Errors.Contract{}} = Chat.Client.new(adapter, id: "invalid")
    end

    assert {:error, %Chat.Errors.Contract{}} = Chat.Client.new(F.FirstAdapter, id: "")
    assert {:error, %Chat.Errors.Contract{}} = Chat.Client.new(F.FirstAdapter, id: "one", id: "two")
    refute_receive {:contract_invoke, _, _, _, _, _}
    refute_receive {:contract_normalize, _, _, _}
  end

  @tag obligation: "jido_chat.adapter.I2"
  test "immutable clients and the same SendMessage Action work for two independent adapters" do
    for adapter <- [F.FirstAdapter, F.SecondAdapter], id <- ["alpha", "beta"] do
      client = F.client(adapter, id)
      before = client
      assert client.credentials == %{token: "private-token:" <> id}
      assert client.config[:private_setting] == "private-config:" <> id
      assert client.source == "urn:jido:chat:client:" <> Base.url_encode64(id, padding: false)
      refute inspect(client) =~ "private"
      options = Chat.Client.options(client)
      assert options[:token] == "private-token:" <> id
      assert options[:transport] == F
      refute_receive {:contract_invoke, _, _, _, _, _}

      request = F.request(Chat.SendMessage, client)

      assert {:ok, %{signal: completed}} =
               Jido.Exec.run(Chat.SendMessage, %{signal: request}, %{client: client}, max_attempts: 1)

      assert_receive {:contract_invoke, ^adapter, ^id, ^request, [], _}
      assert completed.data["result"]["id"] == inspect(adapter) <> ":provider-id"

      assert completed.subject ==
               "conversation:" <>
                 Base.url_encode64(id, padding: false) <> ":" <> Base.url_encode64("room/1", padding: false)

      assert completed.source == client.source
      assert client == before
      assert F.round_trip(completed) == completed
    end
  end

  @tag obligation: "jido_chat.adapter.I3"
  test "all unsupported operations return typed rejections without I/O or source consumption" do
    caller = self()

    stream =
      Stream.map(["Hello"], fn text ->
        send(caller, :source_consumed)
        text
      end)

    for id <- ["alpha", "beta"] do
      client = F.client(F.UnsupportedAdapter, id)
      assert :ok = Chat.AdapterTestKit.Assertions.assert_unsupported_operations(client)

      for {_definition, action} <- F.pairs() do
        request = F.request(action, client)
        opts = if action == Chat.StreamText, do: [stream: stream], else: []
        assert {:error, %Chat.Error{code: :unsupported, signal: failed}} = Chat.execute(client, request, options: opts)
        assert failed.type == Module.concat(action, Failed).type()
        assert failed.data["outcome"] == "not_attempted"
        assert failed.data["operation"] == request.type
        assert F.round_trip(failed) == failed
      end
    end

    refute_receive :unsupported_provider_called
    refute_receive :source_consumed
  end

  @tag obligation: "jido_chat.adapter.I4"
  test "provider Actions and facts extend configured discovery and execution without core edits" do
    client = F.client(F.ExtendedAdapter)
    assert Chat.operations(client) == Enum.sort(F.pairs() ++ [{F.ProviderRequest, F.ProviderAction}])
    assert Enum.sort(Chat.actions(client)) == (Enum.map(F.pairs(), &elem(&1, 1)) ++ [F.ProviderAction]) |> Enum.sort()
    assert Chat.event_definitions(client) == [F.ProviderFact, Chat.Signal.MessageReceived]

    assert Enum.sort(Chat.signal_definitions(client)) ==
             (Chat.signal_definitions() ++ F.ProviderAction.signal_definitions() ++ [F.ProviderFact])
             |> Enum.uniq()
             |> Enum.sort()

    refute F.ProviderRequest in Chat.signal_definitions()
    refute F.ProviderFact in Chat.event_definitions()

    for execute <- [:chat, :exec] do
      request = F.ProviderRequest.new!(%{"client_id" => client.id, "request_id" => Atom.to_string(execute)})

      result =
        case execute do
          :chat ->
            Chat.execute(client, request, options: [local_setting: "private-config"])

          :exec ->
            case Jido.Exec.run(
                   F.ProviderAction,
                   %{signal: request},
                   %{client: client, options: [local_setting: "private-config"]},
                   max_attempts: 1
                 ) do
              {:ok, %{signal: signal}} -> {:ok, signal}
            end
        end

      assert {:ok, completed} = result
      assert completed.data["result"] == %{"status" => "ready"}
      assert_receive {:provider_extension, ^request, [local_setting: "private-config"]}
      assert F.round_trip(completed, Chat.catalog(client)) == completed
      assert {:error, _} = Jido.Signal.Catalog.validate(Chat.catalog(), completed)
    end

    fact =
      F.ProviderFact.new!(
        %{"delivery_id" => "delivery-1", "item_id" => "provider-1", "room_id" => "room/1", "online" => true},
        source: client.source,
        subject: Chat.Signal.Identity.conversation_subject(client.id, "room/1")
      )

    assert {:ok, delivery} = Chat.Delivery.new(client, "delivery-1", [fact])
    assert {:ok, ^delivery} = Chat.normalize(client, delivery)
    assert F.round_trip(fact, Chat.catalog(client)) == fact
    assert {:error, _} = Chat.Delivery.new(F.client(), "delivery-1", [fact])
  end

  @tag obligation: "jido_chat.adapter.I5"
  test "normalization preserves ordered scoped facts and rejects the whole invalid batch" do
    for id <- ["alpha", "beta"] do
      client = F.client(F.FirstAdapter, id)
      first = F.message(client)
      second = F.message(client, %{"item_id" => "item-2", "message_id" => "message-2"})
      delivery = %Chat.Delivery{id: "delivery-1", signals: [second, first]}
      assert {:ok, ^delivery} = Chat.normalize(client, delivery)
      assert_receive {:contract_normalize, ^id, ^delivery, []}
      assert {:ok, empty} = Chat.Delivery.new(client, "delivery-empty", [])
      assert empty.signals == []

      invalid = [
        %{first | source: F.client(F.FirstAdapter, "foreign").source},
        %{first | subject: "conversation:foreign"},
        %{first | data: Map.put(first.data, "delivery_id", "foreign")},
        %{first | data: Map.put(first.data, "text", self())},
        F.request(Chat.SendMessage, client)
      ]

      for bad <- invalid do
        input = %{delivery | signals: [second, bad, first]}
        assert {:error, %Chat.Errors.Contract{}} = Chat.normalize(client, input)
        assert_receive {:contract_normalize, ^id, ^input, []}
      end
    end

    narrow = F.client(F.ExtendedAdapter)
    core = F.message(narrow)

    undeclared =
      Chat.Signal.ThreadStarted.new!(
        %{"item_id" => "topic", "delivery_id" => "delivery-1", "room_id" => "room/1", "thread_id" => "thread"},
        source: narrow.source,
        subject: core.subject
      )

    assert {:error, %Chat.Errors.Contract{}} = Chat.Delivery.new(narrow, "delivery-1", [core, undeclared])
    assert {:error, %Chat.Errors.Contract{}} = Chat.Delivery.new(narrow, "", [core])
    assert {:error, %Chat.Errors.Contract{}} = Chat.Delivery.new(narrow, "delivery-1", :invalid)
  end

  @tag obligation: "jido_chat.adapter.I6"
  test "normalization calls once, keeps options private, and rejects malformed or raised returns" do
    client = F.client()
    input = %Chat.Delivery{id: "delivery-1", signals: [F.message(client)]}
    assert {:ok, ^input} = Chat.normalize(client, input, local_setting: "private-config")
    assert_receive {:contract_normalize, "alpha", ^input, [local_setting: "private-config"]}
    refute_receive {:contract_normalize, _, _, _}

    for response <- [
          nil,
          :raw,
          {:ok, %{}},
          {:ok, [F.message(client)]},
          {:error, "private normalization details"},
          :raise,
          :throw
        ] do
      assert {:error, %Chat.Errors.Contract{} = error} = Chat.normalize(client, input, normalize_return: response)
      refute inspect(error) =~ "private normalization"
      assert_receive {:contract_normalize, "alpha", ^input, _}
      refute_receive {:contract_normalize, _, _, _}
    end

    refute_receive {:contract_invoke, _, _, _, _, _}
  end
end
