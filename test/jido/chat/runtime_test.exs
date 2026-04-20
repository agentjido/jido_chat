defmodule Jido.Chat.RuntimeTest do
  use ExUnit.Case, async: true

  alias Jido.Chat

  alias Jido.Chat.{
    Attachment,
    ActionEvent,
    Author,
    Card,
    CapabilityMatrix,
    ChannelInfo,
    EventEnvelope,
    Incoming,
    IngressResult,
    Markdown,
    MessagePage,
    Modal,
    ModalResult,
    PostPayload,
    Postable,
    Response,
    SlashCommandEvent,
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
    def send_file(room_id, file, opts) do
      send(self(), {:send_file, room_id, file, opts})

      {:ok,
       Response.new(%{
         external_message_id: "file_#{room_id}",
         external_room_id: room_id,
         status: :sent,
         channel_type: :test,
         metadata: %{caption: opts[:caption] || opts[:text]}
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

    @impl true
    def open_thread(room_id, message_id, _opts) do
      {:ok,
       %{
         external_room_id: room_id,
         external_thread_id: "thr_#{message_id}",
         delivery_external_room_id: "delivery_#{message_id}",
         metadata: %{root_message_id: message_id}
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

  defmodule EditFallbackAdapter do
    use Jido.Chat.Adapter

    @impl true
    def channel_type, do: :edit_fallback

    @impl true
    def transform_incoming(payload) when is_map(payload), do: {:ok, Incoming.new(payload)}

    @impl true
    def send_message(room_id, text, _opts) do
      send(self(), {:fallback_send, room_id, text})

      {:ok,
       Response.new(%{
         external_message_id: "stream_msg_#{room_id}",
         external_room_id: room_id,
         channel_type: :edit_fallback,
         metadata: %{sent: text}
       })}
    end

    @impl true
    def edit_message(room_id, message_id, text, _opts) do
      send(self(), {:fallback_edit, room_id, message_id, text})

      {:ok,
       Response.new(%{
         external_message_id: message_id,
         external_room_id: room_id,
         status: :edited,
         channel_type: :edit_fallback,
         metadata: %{edited: text}
       })}
    end
  end

  defmodule RichPostAdapter do
    use Jido.Chat.Adapter

    @impl true
    def channel_type, do: :rich

    @impl true
    def transform_incoming(payload) when is_map(payload), do: {:ok, Incoming.new(payload)}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok,
       Response.new(%{
         external_message_id: "msg_#{room_id}",
         external_room_id: room_id,
         channel_type: :rich
       })}
    end

    @impl true
    def post_message(room_id, %PostPayload{} = payload, opts) do
      send(self(), {:post_message, room_id, payload, opts})

      {:ok,
       Response.new(%{
         external_message_id: "post_#{room_id}",
         external_room_id: room_id,
         channel_type: :rich,
         metadata: %{attachments: length(payload.attachments || [])}
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

  test "dedupe window is bounded by metadata.dedupe_limit" do
    chat =
      Chat.new(adapters: %{test: TestAdapter}, metadata: %{dedupe_limit: 2})
      |> Chat.on_new_message(~r/.*/, fn _thread, _incoming -> send(self(), :handled) end)

    incoming_1 =
      Incoming.new(%{
        external_room_id: "room-3",
        external_user_id: "user-3",
        external_message_id: "dedupe-a",
        text: "hello a"
      })

    incoming_2 = %{incoming_1 | external_message_id: "dedupe-b", text: "hello b"}
    incoming_3 = %{incoming_1 | external_message_id: "dedupe-c", text: "hello c"}

    assert {:ok, chat, %Incoming{}} =
             Chat.process_message(chat, :test, "test:room-3", incoming_1, [])

    assert {:ok, chat, %Incoming{}} =
             Chat.process_message(chat, :test, "test:room-3", incoming_2, [])

    assert {:ok, chat, %Incoming{}} =
             Chat.process_message(chat, :test, "test:room-3", incoming_3, [])

    assert MapSet.size(chat.dedupe) == 2
    assert length(chat.dedupe_order) == 2

    assert {:ok, _chat, %Incoming{}} =
             Chat.process_message(chat, :test, "test:room-3", incoming_1, [])

    assert_received :handled
    assert_received :handled
    assert_received :handled
    assert_received :handled
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
    assert sent.id == "file_room-postable"
    assert [%{kind: :image}] = Enum.map(sent.attachments, &Map.from_struct/1)
    assert_received {:send_file, "room-postable", %{kind: :image}, upload_opts}
    assert upload_opts[:caption] == "**hello**"
    assert upload_opts[:text] == "**hello**"
    assert upload_opts[:thread_id] == nil
  end

  test "thread post flattens typed card payloads through text fallback" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    thread = Chat.thread(chat, :test, "room-card", [])

    card =
      Card.new(%{
        title: "Deploy",
        summary: "Ready",
        components: [
          Card.fields([Card.field("Version", "1.2.3")]),
          Card.actions([Card.button("Approve", "deploy:approve")])
        ]
      })

    assert {:ok, %SentMessage{} = sent} = Thread.post(thread, Postable.card(card))
    assert sent.text =~ "Deploy"
    assert sent.text =~ "Version: 1.2.3"
    assert sent.id == "msg_room-card"
  end

  test "thread send_file routes through adapter upload callback" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    thread = Chat.thread(chat, :test, "room-file", [])

    assert {:ok, %SentMessage{} = sent} =
             Thread.send_file(thread, "/tmp/report.pdf", caption: "report")

    assert sent.id == "file_room-file"
    assert sent.text == "report"

    assert [%{filename: "report.pdf", kind: :file}] =
             Enum.map(sent.attachments, &Map.from_struct/1)

    assert_received {:send_file, "room-file", "/tmp/report.pdf", [caption: "report"]}
  end

  test "thread enumerable post routes through adapter stream callback" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    thread = Chat.thread(chat, :test, "room-stream-post", [])

    assert {:ok, %SentMessage{} = sent} = Thread.post(thread, ["a", "b", "c"])
    assert sent.id == "stream_room-stream-post"
    assert_received {:stream, "room-stream-post", "abc"}
  end

  test "thread post routes stream postables through adapter stream callback" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    thread = Chat.thread(chat, :test, "room-stream-postable", [])

    assert {:ok, %SentMessage{} = sent} =
             Thread.post(thread, Postable.stream(["a", "b", "c"]))

    assert sent.id == "stream_room-stream-postable"
    assert_received {:stream, "room-stream-postable", "abc"}
  end

  test "stream fallback posts placeholder then edits structured output without native stream" do
    chat = Chat.new(adapters: %{edit_fallback: EditFallbackAdapter})
    thread = Chat.thread(chat, :edit_fallback, "room-stream-fallback", [])

    assert {:ok, %SentMessage{} = sent} =
             Thread.post(
               thread,
               Postable.stream([
                 "alpha",
                 %{kind: :step_start, payload: %{label: "Plan"}},
                 %{kind: :plan, payload: ["one", "two"]},
                 "omega"
               ]),
               placeholder_text: "working",
               fallback_mode: :post_edit,
               update_every: 2
             )

    assert sent.id == "stream_msg_room-stream-fallback"
    assert sent.response.metadata.stream_fallback == :post_edit
    assert_received {:fallback_send, "room-stream-fallback", "working"}

    assert_received {:fallback_edit, "room-stream-fallback", "stream_msg_room-stream-fallback",
                     first_edit}

    assert first_edit =~ "alpha"
    assert first_edit =~ "Plan"

    assert_received {:fallback_edit, "room-stream-fallback", "stream_msg_room-stream-fallback",
                     final_edit}

    assert final_edit =~ "- one"
    assert final_edit =~ "omega"
  end

  test "adapter render helpers expose canonical markdown and card payloads" do
    markdown =
      Markdown.root([
        Markdown.heading(3, "Plan"),
        Markdown.list(["one", "two"])
      ])

    card = Card.new(%{title: "Status", components: [Card.button("Run", "run")]})

    assert Jido.Chat.Adapter.render_markdown(markdown) =~ "### Plan"
    assert %{"title" => "Status"} = Jido.Chat.Adapter.render_card(card)
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

  test "open_modal accepts typed modal payloads" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    thread = Chat.thread(chat, :test, "room-modal-typed", [])

    modal =
      Modal.new(%{
        title: "Feedback",
        callback_id: "feedback",
        elements: [Modal.text_input("summary", "Summary")]
      })

    assert {:ok, %ModalResult{} = result} = Thread.open_modal(thread, modal)
    assert result.external_room_id == "room-modal-typed"

    assert_received {:open_modal, "room-modal-typed",
                     %{
                       "title" => "Feedback",
                       "callback_id" => "feedback",
                       "elements" => [%{"id" => "summary", "kind" => :text_input}]
                     }}
  end

  test "filtered action handlers run before catch-all handlers and preserve event context" do
    chat =
      Chat.new(adapters: %{test: TestAdapter})
      |> Chat.on_action("deploy:approve", fn _event -> send(self(), {:action_hit, 1}) end)
      |> Chat.on_action(fn _event -> send(self(), {:action_hit, 2}) end)

    assert {:ok, _chat, %ActionEvent{} = event} =
             Chat.process_action(
               chat,
               :test,
               %{
                 thread_id: "test:room-action:thread-1",
                 channel_id: "test:room-action",
                 message_id: "msg-1",
                 action_id: "deploy:approve",
                 trigger_id: "trigger-1",
                 metadata: %{related_message_id: "msg-root"}
               },
               []
             )

    assert %Thread{id: "test:room-action:thread-1"} = event.thread
    assert %Jido.Chat.ChannelRef{id: "test:room-action"} = event.channel
    assert %Jido.Chat.Message{id: "msg-1"} = event.message
    assert %Jido.Chat.Message{id: "msg-root"} = event.related_message
    assert_receive {:action_hit, 1}
    assert_receive {:action_hit, 2}

    assert {:ok, %ModalResult{external_room_id: "room-action"}} =
             ActionEvent.open_modal(event, Modal.new(%{title: "Approval"}))
  end

  test "filtered slash command handlers match identifiers and expose modal helpers" do
    chat =
      Chat.new(adapters: %{test: TestAdapter})
      |> Chat.on_slash_command("/deploy", fn _event -> send(self(), :slash_specific) end)
      |> Chat.on_slash_command(fn _event -> send(self(), :slash_all) end)

    assert {:ok, _chat, %SlashCommandEvent{} = event} =
             Chat.process_slash_command(
               chat,
               :test,
               %{
                 command: "/deploy",
                 channel_id: "test:room-slash",
                 trigger_id: "trigger-2"
               },
               []
             )

    assert %Jido.Chat.ChannelRef{id: "test:room-slash"} = event.channel
    assert_receive :slash_specific
    assert_receive :slash_all

    assert {:ok, %ModalResult{external_room_id: "room-slash"}} =
             SlashCommandEvent.open_modal(event, Modal.new(%{title: "Deploy"}))
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

    assert {:ok, %SentMessage{} = edited} =
             SentMessage.edit(sent, Postable.markdown("**updated**"))

    assert edited.response.status == :edited
    assert edited.text == "**updated**"

    assert {:error, :edit_attachments_unsupported} =
             SentMessage.edit(sent, Postable.text("updated", files: ["/tmp/report.pdf"]))

    assert :ok = SentMessage.delete(sent)
    assert_received {:deleted, "room-6", "msg_room-6"}

    assert :ok = SentMessage.add_reaction(sent, "👍")
    assert_received {:reaction_add, "room-6", "msg_room-6", "👍"}

    assert :ok = SentMessage.remove_reaction(sent, "👍")
    assert_received {:reaction_remove, "room-6", "msg_room-6", "👍"}
  end

  test "emoji helpers render named reactions for lifecycle APIs" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    thread = Chat.thread(chat, :test, "room-emoji", [])

    assert {:ok, %SentMessage{} = sent} = Thread.post(thread, "emoji")
    assert Chat.emoji(:rocket) == "🚀"
    assert Chat.emoji(":custom_deploy:", custom: %{custom_deploy: "<deploy>"}) == "<deploy>"

    assert :ok = SentMessage.add_reaction(sent, :thumbs_up)
    assert_received {:reaction_add, "room-emoji", "msg_room-emoji", "👍"}
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
    assert ephemeral.text == "secret"
  end

  test "ephemeral card payloads use canonical fallback text through DM fallback" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    thread = Chat.thread(chat, :test, "room-ephemeral-card", [])

    card =
      Card.new(%{
        title: "Secret",
        components: [Card.field("Scope", "private")]
      })

    assert {:ok, ephemeral} =
             Thread.post_ephemeral(
               thread,
               "user-ephemeral-card",
               Postable.card(card),
               fallback_to_dm: true
             )

    assert ephemeral.used_fallback == true
    assert ephemeral.text =~ "Secret"
    assert ephemeral.text =~ "Scope: private"
  end

  test "ephemeral payloads can use file delivery through DM fallback" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    thread = Chat.thread(chat, :test, "room-ephemeral-file", [])

    assert {:ok, ephemeral} =
             Thread.post_ephemeral(
               thread,
               "user-ephemeral",
               Postable.text("secret", files: [%{path: "/tmp/report.pdf"}]),
               fallback_to_dm: true
             )

    assert ephemeral.used_fallback == true
    assert ephemeral.text == "secret"
    assert [%{filename: "report.pdf"}] = Enum.map(ephemeral.attachments, &Map.from_struct/1)
  end

  test "ephemeral file payloads are rejected without DM fallback" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    channel = Chat.channel(chat, :test, "chan-ephemeral-file")

    assert {:error, :ephemeral_attachments_unsupported} =
             Jido.Chat.ChannelRef.post_ephemeral(
               channel,
               "user-ephemeral",
               Postable.text("secret", files: [%{path: "/tmp/report.pdf"}])
             )
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

  test "channel send_file and open_thread return typed handles" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    channel = Chat.channel(chat, :test, "chan-files")

    assert {:ok, %SentMessage{} = sent} =
             Jido.Chat.ChannelRef.send_file(
               channel,
               %{type: :image, url: "https://example.com/photo.jpg", media_type: "image/jpeg"},
               text: "caption"
             )

    assert sent.id == "file_chan-files"

    assert [%{kind: :image, media_type: "image/jpeg"}] =
             Enum.map(sent.attachments, &Map.from_struct/1)

    assert {:ok, %Thread{} = thread} =
             Jido.Chat.ChannelRef.open_thread(channel, "root-123")

    assert thread.external_room_id == "chan-files"
    assert thread.external_thread_id == "thr_root-123"
    assert thread.id == "test:chan-files:thr_root-123"
  end

  test "open_dm infers adapter from author metadata, prefixed ids, and single-adapter chats" do
    chat = Chat.new(adapters: %{test: TestAdapter})

    author =
      Author.new(%{
        user_id: "user-author",
        user_name: "author",
        metadata: %{adapter_name: :test}
      })

    assert {:ok, %Thread{external_room_id: "dm-user-author", is_dm: true}} =
             Chat.open_dm(chat, author, [])

    assert {:ok, %Thread{external_room_id: "dm-user-prefixed", is_dm: true}} =
             Chat.open_dm(chat, "test:user-prefixed", [])

    assert {:ok, %Thread{external_room_id: "dm-user-inferred", is_dm: true}} =
             Chat.open_dm(chat, "user-inferred", [])
  end

  test "chat open_thread routes through adapter helper" do
    chat = Chat.new(adapters: %{test: TestAdapter})

    assert {:ok, %Thread{} = thread} =
             Chat.open_thread(chat, :test, "room-open-thread", "msg-1")

    assert thread.external_thread_id == "thr_msg-1"
    assert thread.metadata.root_message_id == "msg-1"
    assert thread.metadata.delivery_external_room_id == "delivery_msg-1"
  end

  test "channel post preserves postable payload fields in sent handle" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    channel = Chat.channel(chat, :test, "chan-post")

    assert {:ok, %SentMessage{} = sent} =
             Jido.Chat.ChannelRef.post(channel, Postable.raw(%{alpha: 1}))

    assert sent.raw == %{alpha: 1}
    assert is_binary(sent.text)
  end

  test "channel post routes attachment-bearing payloads through send_file" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    channel = Chat.channel(chat, :test, "chan-post-file")

    assert {:ok, %SentMessage{} = sent} =
             Jido.Chat.ChannelRef.post(
               channel,
               Postable.text("hello")
               |> Map.put(:attachments, [%{kind: :file, filename: "doc.pdf"}])
             )

    assert sent.id == "file_chan-post-file"
    assert [%{kind: :file, filename: "doc.pdf"}] = Enum.map(sent.attachments, &Map.from_struct/1)

    assert_received {:send_file, "chan-post-file", %{kind: :file, filename: "doc.pdf"},
                     upload_opts}

    assert upload_opts[:caption] == "hello"
    assert upload_opts[:text] == "hello"
  end

  test "channel post routes file-bearing payloads through send_file" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    channel = Chat.channel(chat, :test, "chan-post-upload")

    assert {:ok, %SentMessage{} = sent} =
             Jido.Chat.ChannelRef.post(
               channel,
               Postable.text("hello", files: [%{path: "/tmp/report.pdf"}])
             )

    assert sent.id == "file_chan-post-upload"

    assert [%{kind: :file, filename: "report.pdf"}] =
             Enum.map(sent.attachments, &Map.from_struct/1)

    assert_received {:send_file, "chan-post-upload", %{path: "/tmp/report.pdf"}, upload_opts}
    assert upload_opts[:caption] == "hello"
    assert upload_opts[:text] == "hello"
  end

  test "channel and thread post reject multiple attachments explicitly" do
    chat = Chat.new(adapters: %{test: TestAdapter})
    channel = Chat.channel(chat, :test, "chan-multi")
    thread = Chat.thread(chat, :test, "thread-multi", [])

    postable =
      Postable.text("hello")
      |> Map.put(:attachments, [%{kind: :image}, %{kind: :file}])

    assert {:error, :multiple_attachments_unsupported} =
             Jido.Chat.ChannelRef.post(channel, postable)

    assert {:error, :multiple_attachments_unsupported} =
             Thread.post(thread, postable)
  end

  test "thread post routes multiple attachments through native post_message callback" do
    chat = Chat.new(adapters: %{rich: RichPostAdapter})
    thread = Chat.thread(chat, :rich, "room-rich", [])

    assert {:ok, %SentMessage{} = sent} =
             Thread.post(
               thread,
               Postable.text("hello")
               |> Map.put(:attachments, [
                 %{path: "/tmp/photo.png", media_type: "image/png"},
                 %{url: "https://example.com/spec.pdf", media_type: "application/pdf"}
               ])
             )

    assert sent.id == "post_room-rich"

    assert [
             %Attachment{kind: :image, path: "/tmp/photo.png", filename: "photo.png"},
             %Attachment{kind: :file, url: "https://example.com/spec.pdf"}
           ] = sent.attachments

    assert_received {:post_message, "room-rich", %PostPayload{} = payload, []}
    assert length(payload.attachments) == 2
    assert Enum.map(payload.attachments, & &1.kind) == [:image, :file]
  end

  test "channel post routes multiple attachments through native post_message callback" do
    chat = Chat.new(adapters: %{rich: RichPostAdapter})
    channel = Chat.channel(chat, :rich, "chan-rich")

    assert {:ok, %SentMessage{} = sent} =
             Jido.Chat.ChannelRef.post(
               channel,
               Postable.text("hello")
               |> Map.put(:attachments, [
                 %{path: "/tmp/voice.ogg", media_type: "audio/ogg"},
                 %{url: "https://example.com/clip.mp4", media_type: "video/mp4"}
               ])
             )

    assert sent.id == "post_chan-rich"
    assert Enum.map(sent.attachments, & &1.kind) == [:audio, :video]
    assert_received {:post_message, "chan-rich", %PostPayload{} = payload, []}
    assert Enum.map(payload.attachments, & &1.kind) == [:audio, :video]
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

  test "filtered reaction and modal handlers only fire on matching identifiers" do
    chat =
      Chat.new(adapters: %{test: TestAdapter})
      |> Chat.on_reaction("👍", fn _event -> send(self(), :reaction_specific) end)
      |> Chat.on_modal_submit("feedback", fn _event -> send(self(), :modal_submit_specific) end)
      |> Chat.on_modal_close("feedback", fn _event -> send(self(), :modal_close_specific) end)

    assert {:ok, _chat, _event} =
             Chat.process_reaction(chat, :test, %{thread_id: "test:room-r", emoji: "👍"}, [])

    assert {:ok, _chat, _event} =
             Chat.process_modal_submit(chat, :test, %{callback_id: "feedback"}, [])

    assert {:ok, _chat, _event} =
             Chat.process_modal_close(chat, :test, %{callback_id: "feedback"}, [])

    assert_received :reaction_specific
    assert_received :modal_submit_specific
    assert_received :modal_close_specific

    assert {:ok, _chat, _event} = Chat.process_reaction(chat, :test, %{emoji: "👎"}, [])
    refute_received :reaction_specific
  end

  test "assistant events gain thread and channel handles" do
    chat = Chat.new(adapters: %{test: TestAdapter})

    assert {:ok, _chat, assistant_started} =
             Chat.process_assistant_thread_started(chat, :test, %{
               thread_id: "test:room-assistant:thr-1",
               channel_id: "test:room-assistant"
             })

    assert %Thread{id: "test:room-assistant:thr-1"} = assistant_started.thread
    assert %Jido.Chat.ChannelRef{id: "test:room-assistant"} = assistant_started.channel

    assert {:ok, _chat, assistant_changed} =
             Chat.process_assistant_context_changed(chat, :test, %{
               thread_id: "test:room-assistant:thr-1",
               channel_id: "test:room-assistant",
               context: %{phase: :thinking}
             })

    assert %Thread{id: "test:room-assistant:thr-1"} = assistant_changed.thread
    assert assistant_changed.context == %{phase: :thinking}
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

  test "route_request returns transport-agnostic ingress result" do
    chat = Chat.new(adapters: %{test: TestAdapter})

    request =
      WebhookRequest.new(%{
        adapter_name: :test,
        headers: %{"x-test" => "1"},
        payload: %{
          external_room_id: "room-req",
          external_user_id: "user-req",
          external_message_id: "req-2",
          text: "hello"
        }
      })

    assert {:ok, %IngressResult{} = result} = Chat.route_request(chat, :test, request, [])
    assert result.mode == :request
    assert %Chat{} = result.chat
    assert %EventEnvelope{event_type: :message} = result.event
    assert %WebhookResponse{status: 200} = result.response
    assert %WebhookRequest{} = result.request
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

  test "route_event returns transport-agnostic ingress result" do
    chat =
      Chat.new(adapters: %{test: TestAdapter})
      |> Chat.on_reaction(fn _event -> send(self(), :reaction_event) end)

    envelope =
      EventEnvelope.new(%{
        adapter_name: :test,
        event_type: :reaction,
        payload: %{thread_id: "t1", emoji: "👍", added: true}
      })

    assert {:ok, %IngressResult{} = result} = Chat.route_event(chat, :test, envelope, [])
    assert result.mode == :event
    assert is_nil(result.response)
    assert %EventEnvelope{event_type: :reaction} = result.event
    assert_received :reaction_event
  end

  test "route_event wraps failures as typed ingress error" do
    chat = Chat.new(adapters: %{test: TestAdapter})

    assert {:error, %Jido.Chat.Errors.Ingress{} = error} =
             Chat.route_event(chat, :test, %{event_type: :invalid, payload: %{}}, [])

    assert error.transport == :event
    assert error.adapter_name == :test
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
