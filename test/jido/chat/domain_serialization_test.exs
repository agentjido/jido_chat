defmodule Jido.Chat.DomainSerializationTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{
    Card,
    ChannelInfo,
    FetchOptions,
    FileUpload,
    Markdown,
    Message,
    MessagePage,
    MessageSubject,
    Modal,
    ReplyContext,
    StreamChunk,
    ThreadPage,
    ThreadSummary,
    UserInfo,
    WebhookRequest,
    WebhookResponse
  }

  test "retained records serialize independently without a public wrapper reviver" do
    values = [
      {Message,
       Message.new(%{
         id: "one",
         text: "hello",
         external_reply_to_id: "transport-parent",
         reply_context: %{id: "quote", text: "parent"}
       })},
      {ReplyContext, ReplyContext.new(%{id: "quote", text: "parent"})},
      {FileUpload, FileUpload.normalize(%{path: "/tmp/report.pdf", media_type: "application/pdf"})},
      {StreamChunk, StreamChunk.new(%{kind: :status, text: "working"})},
      {Markdown, Markdown.root([Markdown.heading(2, "Release"), Markdown.paragraph("Ready")])},
      {Card, Card.new(%{title: "Deploy", components: [Card.button("Approve", "deploy:approve")]})},
      {Modal,
       Modal.new(%{title: "Feedback", callback_id: "feedback", elements: [Modal.text_input("summary", "Summary")]})},
      {UserInfo, UserInfo.new(%{id: "user-1", username: "ada"})},
      {MessageSubject, MessageSubject.new(%{type: "issue", id: "issue-1"})},
      {WebhookRequest, WebhookRequest.new(%{method: "POST", path: "/hook", payload: %{}, headers: %{}})},
      {WebhookResponse, WebhookResponse.new(%{status: 200, body: %{"ok" => true}})}
    ]

    for {module, value} <- values do
      map = module.to_map(value)
      decoded = module.from_map(map)
      assert module.to_map(decoded) == map
    end
  end

  test "canonical pages preserve messages and cursors as pure values" do
    message = Message.new(%{external_room_id: "room-1", external_message_id: "one", text: "hello"})
    page = MessagePage.new(%{messages: [message], next_cursor: "next"})
    assert page.messages == [message]
    assert page.next_cursor == "next"
    summary = ThreadSummary.new(%{id: "thread-1", reply_count: 2, root_message: Map.from_struct(message)})
    assert summary.root_message == message
    assert summary.reply_count == 2
    threads = ThreadPage.new(%{threads: [summary], next_cursor: "thread-next"})
    assert threads.threads == [summary]
    assert threads.next_cursor == "thread-next"
    assert FetchOptions.new(limit: 25, direction: :forward, cursor: "abc").cursor == "abc"
    assert ChannelInfo.new(%{id: "channel-1", name: "general", is_dm: false}).name == "general"
  end

  test "UserInfo normalizes atom and string keyed input" do
    assert %UserInfo{id: "42", username: "ada", display_name: "Ada Lovelace", is_bot: false} =
             UserInfo.new(%{user_id: 42, user_name: "ada", full_name: "Ada Lovelace"})

    assert %UserInfo{id: "u2", username: "grace", is_bot: true} =
             UserInfo.new(%{"id" => "u2", "username" => "grace", "is_bot" => true})
  end

  test "MessageSubject normalizes atom and string keyed input" do
    assert %MessageSubject{
             type: "pull_request",
             id: "38",
             title: "Resource contracts",
             status: "open",
             metadata: %{"draft" => false}
           } =
             MessageSubject.new(%{
               "type" => "pull_request",
               "id" => 38,
               "title" => "Resource contracts",
               "url" => "https://example.com/pull/38",
               "status" => "open",
               "metadata" => %{"draft" => false}
             })
  end
end
