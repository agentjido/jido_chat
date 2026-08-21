defmodule Jido.Chat.AdapterTestKitTest do
  use ExUnit.Case, async: true

  import Jido.Chat.AdapterTestKit.Assertions

  alias Jido.Chat.{Adapter, EventEnvelope, Incoming, Media, Message, Response, WebhookRequest}

  alias Jido.Chat.AdapterTestKit.{
    Factories,
    MockAdapter,
    MockState,
    MockTransport
  }

  defmodule MissingCallbackAdapter do
    use Adapter

    @impl true
    def transform_incoming(payload), do: {:ok, payload}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok, %{external_message_id: "message-1", external_room_id: room_id}}
    end

    @impl true
    def capabilities, do: %{send_message: :native, edit_message: :native}
  end

  defmodule MissingCoreCallbackAdapter do
    use Adapter

    @impl true
    def transform_incoming(payload), do: {:ok, payload}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok, %{external_message_id: "message-1", external_room_id: room_id}}
    end

    @impl true
    def capabilities, do: %{send_message: :native, post_message: :native}
  end

  defmodule UnsupportedCallbackAdapter do
    use Adapter

    @impl true
    def transform_incoming(payload), do: {:ok, payload}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok, %{external_message_id: "message-1", external_room_id: room_id}}
    end

    @impl true
    def edit_message(room_id, message_id, _text, _opts) do
      send(self(), :unsupported_edit_message_called)
      {:ok, %{external_message_id: message_id, external_room_id: room_id}}
    end

    @impl true
    def capabilities, do: %{send_message: :native, edit_message: :unsupported}
  end

  defmodule UnsupportedSendMessageAdapter do
    use Adapter

    @impl true
    def transform_incoming(payload), do: {:ok, payload}

    @impl true
    def send_message(room_id, _text, _opts) do
      send(self(), :unsupported_send_message_called)
      {:ok, %{external_message_id: "message-1", external_room_id: room_id}}
    end

    @impl true
    def capabilities, do: %{send_message: :unsupported}
  end

  defmodule InvalidStatusAdapter do
    use Adapter

    @impl true
    def transform_incoming(payload), do: {:ok, payload}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok, %{external_message_id: "message-1", external_room_id: room_id}}
    end

    @impl true
    def capabilities, do: %{send_message: :sometimes}
  end

  defmodule MissingIncomingAdapter do
    def channel_type, do: :missing_incoming

    def send_message(room_id, _text, _opts) do
      {:ok, %{external_message_id: "message-1", external_room_id: room_id}}
    end

    def capabilities, do: %{send_message: :native}
  end

  defmodule FalseFallbackAdapter do
    use Adapter

    @impl true
    def transform_incoming(payload), do: {:ok, payload}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok, %{external_message_id: "message-1", external_room_id: room_id}}
    end

    @impl true
    def capabilities, do: %{send_message: :native, edit_message: :fallback}
  end

  defmodule MinimalAdapter do
    use Adapter

    @impl true
    def transform_incoming(payload), do: {:ok, payload}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok, %{external_message_id: "message-1", external_room_id: room_id}}
    end
  end

  defmodule ContradictoryCoreFallbackAdapter do
    use Adapter

    @impl true
    def transform_incoming(payload), do: {:ok, payload}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok, %{external_message_id: "message-1", external_room_id: room_id}}
    end

    @impl true
    def capabilities do
      %{
        send_message: :native,
        initialize: :unsupported,
        shutdown: :unsupported,
        post_message: :unsupported,
        fetch_metadata: :unsupported,
        fetch_thread: :unsupported,
        post_channel_message: :unsupported,
        stream: :unsupported,
        webhook: :unsupported,
        verify_webhook: :unsupported,
        parse_event: :unsupported,
        format_webhook_response: :unsupported
      }
    end
  end

  describe "canonical factories" do
    test "build deterministic typed adapter values and accept overrides" do
      assert Factories.author() == Factories.author()
      assert Factories.message() == Factories.message()
      assert Factories.event() == Factories.event()

      assert %{user_name: "override"} = Factories.author(user_name: "override")
      assert %Media{kind: :video, filename: "sample.mp4"} = Factories.media(kind: :video)

      assert %Incoming{external_message_id: "external-message-1"} = Factories.incoming()

      assert %Message{id: "message-1", external_message_id: "external-message-1"} =
               Factories.message()

      assert %EventEnvelope{event_type: :message, payload: %Incoming{}} = Factories.event()

      assert %WebhookRequest{payload: %{"text" => "Hello from the test kit"}} =
               Factories.webhook_request()

      assert %Response{external_message_id: "external-message-1"} = Factories.response()
    end
  end

  describe "shared assertions" do
    test "checks capability coherence and reports a missing native callback" do
      assert_capability_coherence(MockAdapter)

      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_capability_coherence(MissingCallbackAdapter)
        end

      assert Exception.message(error) =~ "edit_message"
      assert Exception.message(error) =~ "missing_callback"
    end

    test "does not hide a missing native callback behind a core fallback" do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_capability_coherence(MissingCoreCallbackAdapter)
        end

      assert Exception.message(error) =~ "post_message"
      assert Exception.message(error) =~ "missing_callback"
    end

    test "rejects invalid raw statuses before capability normalization" do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_capability_coherence(InvalidStatusAdapter)
        end

      assert Exception.message(error) =~ "raw capability statuses"
    end

    test "requires the inbound transform callback" do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_capability_coherence(MissingIncomingAdapter)
        end

      assert Exception.message(error) =~ "transform_incoming/1"
    end

    test "rejects fallback declarations without a callback or core fallback" do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_capability_coherence(FalseFallbackAdapter)
        end

      assert Exception.message(error) =~ "edit_message"
      assert Exception.message(error) =~ "missing_fallback"
    end

    test "missing optional callbacks return exact unsupported results through public wrappers" do
      refute Jido.Chat.AdapterTestKit.supported?(MinimalAdapter, :fetch_message)

      unsupported_results = [
        Adapter.send_file(MinimalAdapter, "room-1", "/tmp/test.txt", []),
        Adapter.edit_message(MinimalAdapter, "room-1", "message-1", "updated", []),
        Adapter.delete_message(MinimalAdapter, "room-1", "message-1", []),
        Adapter.start_typing(MinimalAdapter, "room-1", []),
        Adapter.fetch_message(MinimalAdapter, "room-1", "message-1", []),
        Adapter.fetch_media(MinimalAdapter, "media://test", []),
        Adapter.add_reaction(MinimalAdapter, "room-1", "message-1", "thumbs_up", []),
        Adapter.remove_reaction(MinimalAdapter, "room-1", "message-1", "thumbs_up", []),
        Adapter.post_ephemeral(MinimalAdapter, "room-1", "user-1", "test", []),
        Adapter.open_modal(MinimalAdapter, "room-1", %{custom_id: "test-modal"}, []),
        Adapter.fetch_messages(MinimalAdapter, "room-1", []),
        Adapter.fetch_channel_messages(MinimalAdapter, "room-1", []),
        Adapter.list_threads(MinimalAdapter, "room-1", []),
        Adapter.open_thread(MinimalAdapter, "room-1", "message-1", [])
      ]

      assert Enum.all?(unsupported_results, &(&1 == {:error, :unsupported}))
      assert_unsupported_operations(MinimalAdapter)
    end

    test "reports and exercises every unconditional core fallback" do
      capabilities = Adapter.capabilities(MinimalAdapter)

      Enum.each(Adapter.core_fallback_capabilities(), fn capability ->
        assert capabilities[capability] == :fallback
        assert Jido.Chat.AdapterTestKit.supported?(MinimalAdapter, capability)
      end)

      assert {:ok, %Response{external_room_id: "room-1"}} =
               Adapter.post_message(MinimalAdapter, "room-1", Factories.post_payload(), [])

      assert {:ok, %Jido.Chat.ChannelInfo{id: "room-1"}} =
               Adapter.fetch_metadata(MinimalAdapter, "room-1", [])

      assert {:ok, %Jido.Chat.Thread{external_room_id: "room-1"}} =
               Adapter.fetch_thread(MinimalAdapter, "room-1", [])

      assert_unsupported_operations(MinimalAdapter)
    end

    test "canonicalizes unsupported declarations for unconditional core fallbacks" do
      capabilities = Adapter.capabilities(ContradictoryCoreFallbackAdapter)

      Enum.each(Adapter.core_fallback_capabilities(), fn capability ->
        assert capabilities[capability] == :fallback
      end)

      assert_capability_coherence(ContradictoryCoreFallbackAdapter)
      assert_unsupported_operations(ContradictoryCoreFallbackAdapter)
    end

    test "rejects a false unsupported declaration without calling the provider" do
      assert_unsupported_operations(MinimalAdapter)

      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_unsupported_operations(UnsupportedCallbackAdapter)
        end

      assert Exception.message(error) =~ "edit_message"
      refute_received :unsupported_edit_message_called
    end

    test "rejects an unsupported declaration for required message sending" do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_unsupported_operations(UnsupportedSendMessageAdapter)
        end

      assert Exception.message(error) =~ "send_message"
      refute_received :unsupported_send_message_called
    end

    test "checks normalized results, message identifiers, media, and serialization" do
      response = Factories.response()
      message = Factories.message()
      media = Factories.media()
      event = Factories.event()

      assert ^response = assert_normalized_response({:ok, response})
      assert "external-message-1" = assert_message_identifier(response)
      assert "external-message-1" = assert_message_identifier(message)
      assert ^media = assert_media(media, kind: :image, media_type: "image/png")
      assert %EventEnvelope{} = assert_json_round_trip(event)
    end

    test "checks webhook normalization through the public adapter API" do
      assert %EventEnvelope{event_type: :message, message_id: "external-message-1"} =
               assert_webhook_event(MockAdapter, Factories.webhook_request())
    end

    test "checks capability-gated posting, file, edit, delete, reaction, media, and thread results" do
      assert {:ok, response} = Adapter.send_message(MockAdapter, "room-1", "hello", [])

      assert {:ok, %Response{}} =
               assert_capability_result(
                 MockAdapter,
                 :send_file,
                 Adapter.send_file(MockAdapter, "room-1", "/tmp/sample.txt", [])
               )

      assert {:ok, %Response{status: :edited}} =
               assert_capability_result(
                 MockAdapter,
                 :edit_message,
                 Adapter.edit_message(
                   MockAdapter,
                   "room-1",
                   response.external_message_id,
                   "updated",
                   []
                 )
               )

      assert :ok =
               assert_capability_result(
                 MockAdapter,
                 :add_reaction,
                 Adapter.add_reaction(
                   MockAdapter,
                   "room-1",
                   response.external_message_id,
                   "👍",
                   []
                 )
               )

      assert {:ok, "mock-media-bytes"} =
               assert_capability_result(
                 MockAdapter,
                 :fetch_media,
                 Adapter.fetch_media(MockAdapter, "media://sample", [])
               )

      assert {:ok, %Jido.Chat.Thread{}} =
               assert_capability_result(
                 MockAdapter,
                 :open_thread,
                 Adapter.open_thread(
                   MockAdapter,
                   "room-1",
                   response.external_message_id,
                   []
                 )
               )

      assert :ok =
               assert_capability_result(
                 MockAdapter,
                 :delete_message,
                 Adapter.delete_message(MockAdapter, "room-1", response.external_message_id, [])
               )
    end

    test "rejects malformed and unknown capability results" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_capability_result(MockAdapter, :verify_webhook, :invalid)
      end

      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_capability_result(MockAdapter, :provider_extension, :ok)
        end

      assert Exception.message(error) =~ "unknown adapter capability"
    end
  end

  describe "deterministic support" do
    test "mock state snapshots and resets without shared global state" do
      start_supervised!({MockState, initial: %{count: 1}, name: :state})

      assert %{count: 1} = MockState.snapshot(:state)
      assert :ok = MockState.put(:state, :count, 2)
      assert 2 = MockState.get(:state, :count)
      assert %{count: 3} = MockState.update(:state, &Map.update!(&1, :count, fn n -> n + 1 end))
      assert :ok = MockState.reset(:state)
      assert %{count: 1} = MockState.snapshot(:state)
    end

    test "mock transport records calls and consumes queued responses in order" do
      transport =
        start_supervised!({MockTransport, responses: %{send_message: [{:ok, %{id: "one"}}]}})

      assert {:ok, %{id: "one"}} =
               MockTransport.request(transport, :send_message, %{text: "first"}, :default)

      assert :default =
               MockTransport.request(transport, :send_message, %{text: "second"}, :default)

      assert [
               %{operation: :send_message, payload: %{text: "first"}, sequence: 1},
               %{operation: :send_message, payload: %{text: "second"}, sequence: 2}
             ] = MockTransport.calls(transport)
    end

    test "mock adapter records and normalizes capability-gated operations" do
      transport = start_supervised!(MockTransport)
      opts = [transport: transport]

      assert {:ok, %Response{} = posted} =
               Adapter.send_message(MockAdapter, "room-1", "hello", opts)

      assert posted.external_message_id == "mock-message-1"

      assert {:ok, %Response{status: :edited}} =
               Adapter.edit_message(MockAdapter, "room-1", posted.external_message_id, "edit", opts)

      assert :ok =
               Adapter.add_reaction(MockAdapter, "room-1", posted.external_message_id, "👍", opts)

      assert :ok = Adapter.delete_message(MockAdapter, "room-1", posted.external_message_id, opts)

      assert Enum.map(MockTransport.calls(transport), & &1.operation) == [
               :send_message,
               :edit_message,
               :add_reaction,
               :delete_message
             ]
    end

    test "mock history routes every message field to the requested room" do
      assert {:ok, %Message{} = fetched} =
               Adapter.fetch_message(MockAdapter, "room-9", "message-9", [])

      assert fetched.external_room_id == "room-9"
      assert fetched.channel_id == "room-9"
      assert fetched.thread_id == "test:room-9:provider-thread-1"

      assert {:ok, %{messages: [history_message]}} =
               Adapter.fetch_messages(MockAdapter, "room-9", [])

      assert history_message.external_room_id == "room-9"
      assert history_message.channel_id == "room-9"
      assert history_message.thread_id == "test:room-9:provider-thread-1"

      assert {:ok, %{threads: [%{root_message: root_message}]}} =
               Adapter.list_threads(MockAdapter, "room-9", [])

      assert root_message.external_room_id == "room-9"
      assert root_message.channel_id == "room-9"
      assert root_message.thread_id == "test:room-9:provider-thread-1"
    end
  end
end

defmodule Jido.Chat.AdapterTestKitGeneratedConformanceTest do
  use Jido.Chat.AdapterTestKit, adapter: Jido.Chat.AdapterTestKit.MockAdapter, async: true

  capability_test :edit_message, "provider extension runs only for a supported capability" do
    assert {:ok, %Jido.Chat.Response{status: :edited}} =
             Jido.Chat.Adapter.edit_message(
               @adapter,
               "room-1",
               "external-message-1",
               "updated",
               []
             )
  end
end
