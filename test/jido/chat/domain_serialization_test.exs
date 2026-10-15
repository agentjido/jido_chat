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
    PostPayload,
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

  test "string-key message pages retain normalized message records" do
    message = %{"external_room_id" => "room-1", "external_message_id" => "one", "text" => "hello"}
    page = MessagePage.new(%{"messages" => [message], "next_cursor" => "next"})
    assert page == MessagePage.new(%{messages: [message], next_cursor: "next"})
    assert page.messages == [Message.new(message)]
  end

  test "string-key thread pages retain normalized summary records" do
    summary = %{"id" => "thread-1", "reply_count" => 2}
    page = ThreadPage.new(%{"threads" => [summary], "next_cursor" => "next"})
    assert page == ThreadPage.new(%{threads: [summary], next_cursor: "next"})
    assert page.threads == [ThreadSummary.new(summary)]
  end

  test "string-key thread summaries retain normalized root messages" do
    message = %{"external_room_id" => "room-1", "external_message_id" => "one", "text" => "hello"}
    summary = ThreadSummary.new(%{"id" => "thread-1", "root_message" => message})
    assert summary == ThreadSummary.new(%{id: "thread-1", root_message: message})
    assert summary.root_message == Message.new(message)
  end

  test "string-key webhook requests normalize header names before lookup and serialization" do
    request = WebhookRequest.new(%{"payload" => %{}, "headers" => %{"X-Test" => "value"}})
    assert WebhookRequest.header(request, "x-test") == "value"
    assert WebhookRequest.header(request, "X-TEST") == "value"
    assert request == WebhookRequest.new(%{payload: %{}, headers: %{"X-Test" => "value"}})
    assert WebhookRequest.from_map(WebhookRequest.to_map(request)) == request
  end

  test "string-key cards normalize markdown before fallback rendering" do
    markdown = Markdown.root([Markdown.paragraph("Ready")])

    for input <- ["Ready", markdown, Markdown.to_map(markdown)] do
      card = Card.new(%{"markdown" => input})
      assert card == Card.new(%{markdown: input})
      assert %Markdown{} = card.markdown
      assert Card.fallback_text(card) == "Ready"
      assert Card.to_adapter_payload(card)["fallback_text"] == "Ready"
      decoded = Card.from_map(Card.to_map(card))
      assert %Markdown{} = decoded.markdown
      assert Card.to_map(decoded) == Card.to_map(card)
      assert Card.fallback_text(decoded) == "Ready"
    end
  end

  test "string-key card components keep typed markdown through serialization and fallback rendering" do
    markdown = Markdown.root([Markdown.paragraph("Ready")])

    for input <- ["Ready", markdown, Markdown.to_map(markdown)] do
      component = Card.Component.new(%{"kind" => "section", "markdown" => input})
      assert component == Card.Component.new(%{kind: :section, markdown: input})
      assert %Markdown{} = component.markdown
      decoded = Card.Component.from_map(Card.Component.to_map(component))
      assert %Markdown{} = decoded.markdown
      assert Card.Component.to_map(decoded) == Card.Component.to_map(component)
      card = Card.new(%{components: [component]})
      assert Card.fallback_text(card) == "Ready"
      decoded_card = Card.from_map(Card.to_map(card))
      assert Card.to_map(decoded_card) == Card.to_map(card)
      assert Card.fallback_text(decoded_card) == "Ready"
    end
  end

  test "string-key markdown post payloads convert typed or serialized markdown to text" do
    markdown = Markdown.root([Markdown.paragraph("Ready")])

    for input <- [markdown, Markdown.to_map(markdown)] do
      payload = PostPayload.new(%{"kind" => "markdown", "markdown" => input})
      assert payload == PostPayload.new(%{kind: :markdown, markdown: input})
      assert payload.markdown == "Ready"
      assert payload.text == "Ready"
      decoded = PostPayload.from_map(PostPayload.to_map(payload))
      assert PostPayload.to_map(decoded) == PostPayload.to_map(payload)
      assert PostPayload.display_text(decoded) == "Ready"
    end
  end

  test "rich post payloads retain canonical AST and card values through string-key construction and round trips" do
    markdown = Markdown.root([Markdown.paragraph("Ready")])
    card = Card.new(%{markdown: markdown, components: [Card.section(markdown: markdown)]})

    ast_payload = PostPayload.new(%{"kind" => "ast", "ast" => Markdown.to_map(markdown)})
    assert ast_payload.ast == markdown
    assert ast_payload.text == "Ready"

    card_payload = PostPayload.new(%{"kind" => "card", "card" => Card.to_map(card)})
    assert card_payload.card == card
    assert card_payload.raw == card
    assert card_payload.text == "Ready\n\nReady"

    for payload <- [PostPayload.new(%{kind: :ast, ast: markdown}), PostPayload.new(%{kind: :card, card: card})] do
      decoded = PostPayload.from_map(PostPayload.to_map(payload))
      assert decoded.ast == payload.ast
      assert decoded.card == payload.card
      assert PostPayload.to_map(decoded) == PostPayload.to_map(payload)
      assert PostPayload.display_text(decoded) == PostPayload.display_text(payload)
      if payload.kind == :card, do: assert(decoded.raw == card)
    end
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
