defmodule Jido.Chat.RuntimeTest do
  use ExUnit.Case, async: true

  alias Jido.Chat

  alias Jido.Chat.{
    CapabilityMatrix,
    ChannelInfo,
    EventEnvelope,
    Incoming,
    MessagePage,
    ModalResult,
    Postable,
    Response,
    SentMessage,
    Thread,
    ThreadPage,
    WebhookRequest,
    WebhookResponse
  }

  defmodule TestAdapter do
    use Jido.Chat.Adapter

    @impl true
    def channel_type, do: :test

    @impl true
    def transform_incoming(payload) when is_map(payload), do: {:ok, Incoming.new(payload)}

    @impl true
    def send_message(room_id, text, _opts) do
      {:ok,
       Response.new(%{
         external_message_id: "msg_#{room_id}",
         external_room_id: room_id,
         status: :sent,
         channel_type: :test,
         metadata: %{echo: text}
       })}
    end

    @impl true
    def edit_message(room_id, message_id, text, _opts) do
      {:ok,
       Response.new(%{
         external_message_id: message_id,
         external_room_id: room_id,
         status: :edited,
         channel_type: :test,
         metadata: %{echo: text}
       })}
    end

    @impl true
    def delete_message(room_id, message_id, _opts) do
      send(self(), {:deleted, room_id, message_id})
      :ok
    end

    @impl true
    def start_typing(room_id, opts) do
      send(self(), {:typing, room_id, opts[:status]})
      :ok
    end

    @impl true
    def fetch_metadata(room_id, _opts) do
      {:ok,
       ChannelInfo.new(%{
         id: to_string(room_id),
         name: "room-#{room_id}",
         is_dm: false,
         metadata: %{room_id: room_id}
       })}
    end

    @impl true
    def add_reaction(room_id, message_id, emoji, _opts) do
      send(self(), {:reaction_add, room_id, message_id, emoji})
      :ok
    end

    @impl true
    def remove_reaction(room_id, message_id, emoji, _opts) do
      send(self(), {:reaction_remove, room_id, message_id, emoji})
      :ok
    end

    @impl true
    def open_dm(user_id, _opts), do: {:ok, "dm-#{user_id}"}

    @impl true
    def fetch_messages(room_id, opts) do
      case opts[:cursor] do
        nil ->
          {:ok,
           %{
             messages: [
               %{external_room_id: room_id, external_message_id: "m10", text: "first"},
               %{external_room_id: room_id, external_message_id: "m11", text: "second"}
             ],
             next_cursor: "next-1"
           }}

        "next-1" ->
          {:ok,
           %{
             messages: [
               %{external_room_id: room_id, external_message_id: "m12", text: "third"}
             ],
             next_cursor: nil
           }}

        _ ->
          {:ok, %{messages: [], next_cursor: nil}}
      end
    end

    @impl true
    def stream(room_id, chunks, _opts) do
      text = chunks |> Enum.map(&to_string/1) |> Enum.join("")
      send(self(), {:stream, room_id, text})

      {:ok,
       Response.new(%{
         external_message_id: "stream_#{room_id}",
         external_room_id: room_id,
         status: :sent,
         channel_type: :test,
         metadata: %{streamed: true}
       })}
    end

    @impl true
    def open_modal(room_id, payload, _opts) do
      send(self(), {:open_modal, room_id, payload})

      {:ok,
       %{
         id: "modal_#{room_id}",
         status: :opened,
         external_room_id: room_id,
         raw: payload,
         metadata: %{source: :test}
       }}
    end

    @impl true
    def fetch_channel_messages(room_id, _opts) do
      {:ok,
       %{
         messages: [
           %{external_room_id: room_id, external_message_id: "c1", text: "channel message"}
         ],
         next_cursor: nil
       }}
    end

    @impl true
    def list_threads(room_id, _opts) do
      {:ok,
       %{
         threads: [
           %{
             id: "test:#{room_id}:thread-1",
             reply_count: 2,
             root_message: %{
               external_room_id: room_id,
               external_message_id: "root-1",
               text: "root"
             }
           }
         ],
         next_cursor: nil
       }}
    end
  end

  defmodule NoModalAdapter do
    use Jido.Chat.Adapter

    @impl true
    def channel_type, do: :no_modal

    @impl true
    def transform_incoming(payload) when is_map(payload), do: {:ok, Incoming.new(payload)}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok,
       Response.new(%{
         external_message_id: "m_#{room_id}",
         external_room_id: room_id,
         channel_type: :no_modal
       })}
    end
  end

  defmodule NoopWebhookAdapter do
    use Jido.Chat.Adapter

    @impl true
    def channel_type, do: :noop

    @impl true
    def transform_incoming(payload) when is_map(payload), do: {:ok, Incoming.new(payload)}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok,
       Response.new(%{
         external_message_id: "m_#{room_id}",
         external_room_id: room_id,
         channel_type: :noop
       })}
    end

    @impl true
    def parse_event(_request, _opts), do: {:ok, :noop}

    @impl true
    def format_webhook_response({:ok, _chat, :noop}, _opts) do
      WebhookResponse.new(%{status: 204, body: %{ok: true, noop: true}})
    end
  end

  test "mention handler only fires for unsubscribed threads" do
    chat =
      Chat.new(user_name: "jido", adapters: %{test: TestAdapter})
      |> Chat.on_new_mention(fn _thread, _incoming -> send(self(), :mention) end)
      |> Chat.on_subscribed_message(fn _thread, _incoming -> send(self(), :subscribed) end)

    incoming =
      Incoming.new(%{
        external_room_id: "room-1",
        external_user_id: "user-1",
        external_message_id: "m1",
        text: "@jido hi"
      })

    assert {:ok, chat, %Incoming{}} =
             Chat.process_message(chat, :test, "test:room-1", incoming, [])

    assert_received :mention
    refute_received :subscribed

    chat = Thread.subscribe(chat, Chat.thread(chat, :test, "room-1", id: "test:room-1"))

    incoming_2 = %{incoming | external_message_id: "m2", text: "@jido still here"}

    assert {:ok, _chat, %Incoming{}} =
             Chat.process_message(chat, :test, "test:room-1", incoming_2, [])

    assert_received :subscribed
  end

  test "regex handler routes matching messages" do
    chat =
      Chat.new(adapters: %{test: TestAdapter})
      |> Chat.on_new_message(~r/^ping$/i, fn _thread, _incoming -> send(self(), :regex_hit) end)

    incoming =
      Incoming.new(%{
        external_room_id: "room-2",
        external_user_id: "user-2",
        external_message_id: "m3",
        text: "ping"
      })

    assert {:ok, _chat, %Incoming{}} =
             Chat.process_message(chat, :test, "test:room-2", incoming, [])

    assert_received :regex_hit
  end

  test "dedupe ignores repeated message ids" do
    chat =
      Chat.new(adapters: %{test: TestAdapter})
      |> Chat.on_new_message(~r/.*/, fn _thread, _incoming -> send(self(), :handled) end)

    incoming =
      Incoming.new(%{
        external_room_id: "room-3",
        external_user_id: "user-3",
        external_message_id: "dedupe-1",
        text: "hello"
      })

    assert {:ok, chat, %Incoming{}} =
             Chat.process_message(chat, :test, "test:room-3", incoming, [])

    assert_received :handled

    assert {:ok, _chat, %Incoming{}} =
             Chat.process_message(chat, :test, "test:room-3", incoming, [])

    refute_received :handled
  end

  test "thread post returns sent message handle" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    thread = Chat.thread(chat, :test, "room-4", [])

    assert {:ok, %SentMessage{} = sent} = Thread.post(thread, "hello")
    assert sent.thread_id == "test:room-4"
    assert sent.id == "msg_room-4"
    assert sent.response.status == :sent
    assert sent.response.external_room_id == "room-4"
  end

  test "thread post preserves postable payload fields in sent handle" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    thread = Chat.thread(chat, :test, "room-postable", [])

    assert {:ok, %SentMessage{} = sent} =
             Thread.post(
               thread,
               Postable.markdown("**hello**") |> Map.put(:attachments, [%{kind: :image}]),
               []
             )

    assert sent.text == "**hello**"
    assert sent.formatted == "**hello**"
    assert sent.metadata.format == :markdown
    assert [%{kind: :image}] = Enum.map(sent.attachments, &Map.from_struct/1)
  end

  test "thread enumerable post routes through adapter stream callback" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    thread = Chat.thread(chat, :test, "room-stream-post", [])

    assert {:ok, %SentMessage{} = sent} = Thread.post(thread, ["a", "b", "c"])
    assert sent.id == "stream_room-stream-post"
    assert_received {:stream, "room-stream-post", "abc"}
  end

  test "thread/channel open_modal route through adapter and normalize typed result" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    thread = Chat.thread(chat, :test, "room-modal", [])
    channel = Chat.channel(chat, :test, "room-modal")

    assert {:ok, %ModalResult{} = thread_result} =
             Thread.open_modal(thread, %{custom_id: "feedback", title: "Feedback"})

    assert thread_result.status == :opened
    assert thread_result.external_room_id == "room-modal"

    assert {:ok, %ModalResult{} = channel_result} =
             Jido.Chat.ChannelRef.open_modal(channel, %{custom_id: "feedback", title: "Feedback"})

    assert channel_result.status == :opened
    assert_received {:open_modal, "room-modal", %{custom_id: "feedback", title: "Feedback"}}
  end

  test "open_modal returns unsupported when adapter does not implement it" do
    chat = Chat.new(adapters: %{no_modal: NoModalAdapter})
    thread = Chat.thread(chat, :no_modal, "room-unsupported", [])

    assert {:error, :unsupported} = Thread.open_modal(thread, %{custom_id: "x"})
  end

  test "sent message lifecycle methods dispatch to adapter" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    thread = Chat.thread(chat, :test, "room-6", [])

    assert {:ok, %SentMessage{} = sent} = Thread.post(thread, "hello")

    assert {:ok, %SentMessage{} = edited} = SentMessage.edit(sent, "updated")
    assert edited.response.status == :edited

    assert :ok = SentMessage.delete(sent)
    assert_received {:deleted, "room-6", "msg_room-6"}

    assert :ok = SentMessage.add_reaction(sent, "👍")
    assert_received {:reaction_add, "room-6", "msg_room-6", "👍"}

    assert :ok = SentMessage.remove_reaction(sent, "👍")
    assert_received {:reaction_remove, "room-6", "msg_room-6", "👍"}
  end

  test "thread typing and ephemeral fallback" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    thread = Chat.thread(chat, :test, "room-7", [])

    assert :ok = Thread.start_typing(thread, "working")
    assert_received {:typing, "room-7", "working"}

    assert {:ok, ephemeral} =
             Thread.post_ephemeral(thread, "user-7", "secret", fallback_to_dm: true)

    assert ephemeral.used_fallback == true
    assert ephemeral.thread_id == "test:dm-user-7"
  end

  test "thread messages and all_messages pagination" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    thread = Chat.thread(chat, :test, "room-8", [])

    assert {:ok, %MessagePage{} = page} = Thread.messages(thread, limit: 2)
    assert length(page.messages) == 2
    assert page.next_cursor == "next-1"

    assert {:ok, messages} = Thread.all_messages(thread, limit: 2)
    assert Enum.map(messages, & &1.external_message_id) == ["m10", "m11", "m12"]
  end

  test "channel ref returns typed metadata/messages/threads" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    channel = Chat.channel(chat, :test, "chan-1")

    assert {:ok, %ChannelInfo{} = info} = Jido.Chat.ChannelRef.fetch_metadata(channel)
    assert info.id == "chan-1"

    assert {:ok, %MessagePage{} = messages} = Jido.Chat.ChannelRef.messages(channel)
    assert length(messages.messages) == 1

    assert {:ok, %ThreadPage{} = threads} = Jido.Chat.ChannelRef.threads(channel)
    assert length(threads.threads) == 1
  end

  test "channel post preserves postable payload fields in sent handle" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    channel = Chat.channel(chat, :test, "chan-post")

    assert {:ok, %SentMessage{} = sent} =
             Jido.Chat.ChannelRef.post(channel, Postable.raw(%{alpha: 1}))

    assert sent.raw == %{alpha: 1}
    assert is_binary(sent.text)
  end

  test "webhooks helper returns adapter-keyed typed dispatchers" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    webhooks = Chat.webhooks(chat)

    assert is_function(webhooks.test, 2)

    incoming = %{
      external_room_id: "room-9",
      external_user_id: "user-9",
      external_message_id: "w1",
      text: "hello"
    }

    assert {:ok, _chat, %EventEnvelope{} = envelope, %WebhookResponse{} = response} =
             webhooks.test.(incoming, [])

    assert envelope.event_type == :message
    assert %Incoming{external_message_id: "w1"} = envelope.payload
    assert response.status == 200
  end

  test "webhooks_with_chat compatibility helper accepts explicit chat argument" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    webhooks = Chat.webhooks_with_chat(chat)

    assert is_function(webhooks.test, 3)

    incoming = %{
      external_room_id: "room-9b",
      external_user_id: "user-9b",
      external_message_id: "w9b",
      text: "hello"
    }

    assert {:ok, _chat, %EventEnvelope{} = envelope, %WebhookResponse{} = response} =
             webhooks.test.(chat, incoming, [])

    assert envelope.event_type == :message
    assert response.status == 200
  end

  test "thread and channel state helpers are pure-struct" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    thread = Chat.thread(chat, :test, "room-state", [])
    channel = Chat.channel(chat, :test, "chan-state")

    chat = Thread.set_state(chat, thread, :merge, %{a: 1})
    chat = Thread.set_state(chat, thread, :b, 2)
    assert Thread.state(chat, thread) == %{a: 1, b: 2}
    assert Thread.state(chat, thread, :b) == 2

    chat = Jido.Chat.ChannelRef.set_state(chat, channel, :replace, %{x: 9})
    assert Jido.Chat.ChannelRef.state(chat, channel) == %{x: 9}
  end

  test "event process APIs dispatch registered handlers" do
    chat =
      Chat.new(adapters: %{test: TestAdapter})
      |> Chat.on_reaction(fn _event -> send(self(), :reaction_hit) end)
      |> Chat.on_action(fn _event -> send(self(), :action_hit) end)
      |> Chat.on_modal_submit(fn _event -> send(self(), :modal_submit_hit) end)
      |> Chat.on_modal_close(fn _event -> send(self(), :modal_close_hit) end)
      |> Chat.on_slash_command(fn _event -> send(self(), :slash_hit) end)
      |> Chat.on_assistant_thread_started(fn _event -> send(self(), :assistant_thread_hit) end)
      |> Chat.on_assistant_context_changed(fn _event -> send(self(), :assistant_context_hit) end)

    assert {:ok, _chat, _event} =
             Chat.process_reaction(chat, :test, %{thread_id: "t1", emoji: "👍"}, [])

    assert {:ok, _chat, _event} = Chat.process_action(chat, :test, %{thread_id: "t1"}, [])

    assert {:ok, _chat, _event} =
             Chat.process_modal_submit(chat, :test, %{callback_id: "form"}, [])

    assert {:ok, _chat, _event} =
             Chat.process_modal_close(chat, :test, %{callback_id: "form"}, [])

    assert {:ok, _chat, _event} =
             Chat.process_slash_command(chat, :test, %{command: "/help"}, [])

    assert {:ok, _chat, _event} =
             Chat.process_assistant_thread_started(chat, :test, %{thread_id: "t1"})

    assert {:ok, _chat, _event} =
             Chat.process_assistant_context_changed(chat, :test, %{thread_id: "t1", context: %{}})

    assert_received :reaction_hit
    assert_received :action_hit
    assert_received :modal_submit_hit
    assert_received :modal_close_hit
    assert_received :slash_hit
    assert_received :assistant_thread_hit
    assert_received :assistant_context_hit
  end

  test "process_event routes typed envelopes" do
    chat =
      Chat.new(adapters: %{test: TestAdapter})
      |> Chat.on_reaction(fn _event -> send(self(), :reaction_event) end)

    envelope =
      EventEnvelope.new(%{
        adapter_name: :test,
        event_type: :reaction,
        payload: %{thread_id: "t1", emoji: "👍", added: true}
      })

    assert {:ok, _chat, %EventEnvelope{event_type: :reaction}} =
             Chat.process_event(chat, :test, envelope, [])

    assert_received :reaction_event
  end

  test "handle_webhook_request accepts typed request" do
    chat = Chat.new(adapters: %{test: TestAdapter})

    request =
      WebhookRequest.new(%{
        adapter_name: :test,
        headers: %{"x-test" => "1"},
        payload: %{
          external_room_id: "room-req",
          external_user_id: "user-req",
          external_message_id: "req-1",
          text: "hello"
        }
      })

    assert {:ok, _chat, %EventEnvelope{event_type: :message}, %WebhookResponse{} = response} =
             Chat.handle_webhook_request(chat, :test, request, [])

    assert response.status == 200
  end

  test "handle_webhook_request always returns typed response on unknown adapter" do
    chat = Chat.new(adapters: %{test: TestAdapter})

    assert {:ok, ^chat, nil, %WebhookResponse{} = response} =
             Chat.handle_webhook_request(chat, :missing, %{message: %{}}, [])

    assert response.status == 404
    assert response.body == %{error: "unknown_adapter", adapter_name: "missing"}
  end

  test "handle_webhook_request rescues callback exceptions into typed error response" do
    chat = Chat.new(adapters: %{test: TestAdapter})

    assert {:ok, ^chat, nil, %WebhookResponse{} = response} =
             Chat.handle_webhook_request(chat, :test, %{}, [])

    assert response.status == 500
    assert response.body[:error] == "webhook_exception"
  end

  test "handle_webhook_request supports noop parse path and typed response" do
    chat = Chat.new(adapters: %{noop: NoopWebhookAdapter})

    request =
      WebhookRequest.new(%{
        adapter_name: :noop,
        payload: %{type: "ping"}
      })

    assert {:ok, ^chat, nil, %WebhookResponse{} = response} =
             Chat.handle_webhook_request(chat, :noop, request, [])

    assert response.status == 204
    assert response.body.noop == true
  end

  test "stream helpers page through messages" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    thread = Chat.thread(chat, :test, "room-stream", [])
    channel = Chat.channel(chat, :test, "room-stream")

    messages = thread |> Thread.messages_stream(limit: 2) |> Enum.map(& &1.external_message_id)
    assert messages == ["m10", "m11", "m12"]

    channel_messages =
      channel
      |> Jido.Chat.ChannelRef.messages_stream(limit: 2)
      |> Enum.map(& &1.external_message_id)

    assert channel_messages == ["c1"]
  end

  test "get_adapter and reviver surfaces" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    assert {:ok, TestAdapter} = Chat.get_adapter(chat, :test)
    assert {:ok, %CapabilityMatrix{} = capabilities} = Chat.adapter_capabilities(chat, :test)
    assert capabilities.capabilities.send_message == :native

    encoded = Chat.to_map(chat)
    reviver = Chat.reviver()
    revived = reviver.(encoded)

    assert %Chat{} = revived
    assert revived.id == chat.id
  end
end
