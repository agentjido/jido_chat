defmodule Jido.Chat.AdapterTestKitTest do
  use ExUnit.Case, async: true
  import Jido.Chat.AdapterTestKit.Assertions
  alias Jido.Chat.AdapterTestKit.{Factories, MockAdapter, MockState, MockTransport}

  alias Jido.Chat.Signal.{
    AddReaction,
    DeleteMessage,
    EditMessage,
    FetchMessage,
    FetchMessages,
    ListThreads,
    SendMessage
  }

  test "factories produce domain inputs and fully checked typed deliveries" do
    assert Factories.author().user_name == "test-user"
    assert Factories.media().kind == :image
    assert Factories.message().text == "hello"
    assert Factories.post_payload().kind == :text
    assert Factories.webhook_request().method == "POST"
    assert {:ok, binding} = Jido.Chat.bind(MockAdapter, id: "binding-1")
    signal = Factories.message_received(binding)
    assert :ok = assert_json_round_trip(signal)
    assert {:ok, delivery} = Jido.Chat.Delivery.new(binding, "delivery-1", [signal])
    assert ^delivery = assert_delivery(binding, {:ok, delivery})
    assert :ok = assert_unsupported_operations(MockAdapter)
    assert :ok = assert_capability_coherence(MockAdapter)
    assert {:ok, delivery} = Jido.Chat.normalize_event(binding, %{"id" => "different-delivery", "items" => [%{}]})
    assert hd(delivery.signals).data["delivery_id"] == "different-delivery"
  end

  test "mock state snapshots and resets without shared global state" do
    state = start_supervised!({MockState, initial: %{count: 1}})
    assert %{count: 1} = MockState.snapshot(state)
    assert :ok = MockState.put(state, :count, 2)
    assert 2 = MockState.get(state, :count)
    assert %{count: 3} = MockState.update(state, &Map.update!(&1, :count, fn n -> n + 1 end))
    assert :ok = MockState.reset(state)
    assert %{count: 1} = MockState.snapshot(state)
  end

  test "mock transport records calls and consumes queued responses in order" do
    transport = start_supervised!({MockTransport, responses: %{send_message: [{:ok, %{id: "one"}}]}})
    assert {:ok, %{id: "one"}} = MockTransport.request(transport, :send_message, %{text: "first"}, :default)
    assert :default = MockTransport.request(transport, :send_message, %{text: "second"}, :default)

    assert [
             %{operation: :send_message, payload: %{text: "first"}, sequence: 1},
             %{operation: :send_message, payload: %{text: "second"}, sequence: 2}
           ] = MockTransport.calls(transport)
  end

  test "typed requests select one mock callback in the intended order" do
    transport = start_supervised!(MockTransport)
    assert {:ok, binding} = Jido.Chat.bind(MockAdapter, id: "binding-1", transport: transport)
    base = %{"room_id" => "room-1"}
    send_request = SendMessage.new!(Map.merge(base, %{"request_id" => "send", "text" => "hello"}))
    posted = assert_operation_result(Jido.Chat.execute(binding, send_request))
    assert posted.data["result"]["id"] == "mock-message-1"

    for {definition, data} <- [
          {EditMessage, %{"request_id" => "edit", "message_id" => "mock-message-1", "text" => "edit"}},
          {AddReaction, %{"request_id" => "reaction", "message_id" => "mock-message-1", "reaction" => "👍"}},
          {DeleteMessage, %{"request_id" => "delete", "message_id" => "mock-message-1"}}
        ] do
      result = assert_operation_result(Jido.Chat.execute(binding, definition.new!(Map.merge(base, data))))
      assert result.type == Jido.Chat.Signal.OperationCompleted.type()
    end

    assert Enum.map(MockTransport.calls(transport), & &1.operation) == [
             :send_message,
             :edit_message,
             :add_reaction,
             :delete_message
           ]
  end

  test "history results keep the requested external room separate from thread IDs" do
    assert {:ok, binding} = Jido.Chat.bind(MockAdapter, id: "binding-1")

    fetched =
      assert_operation_result(
        Jido.Chat.execute(
          binding,
          FetchMessage.new!(%{"request_id" => "one", "room_id" => "room-9", "message_id" => "message-9"})
        )
      )

    assert fetched.data["result"]["room_id"] == "room-9"

    history =
      assert_operation_result(
        Jido.Chat.execute(binding, FetchMessages.new!(%{"request_id" => "history", "room_id" => "room-9"}))
      )

    assert hd(history.data["result"]["messages"])["room_id"] == "room-9"

    threads =
      assert_operation_result(
        Jido.Chat.execute(binding, ListThreads.new!(%{"request_id" => "threads", "room_id" => "room-9"}))
      )

    assert threads.data["result"]["threads"] != []
  end
end

defmodule Jido.Chat.AdapterTestKitGeneratedConformanceTest do
  use Jido.Chat.AdapterTestKit, adapter: Jido.Chat.AdapterTestKit.MockAdapter, async: true
end
