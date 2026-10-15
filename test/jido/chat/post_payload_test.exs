defmodule Jido.Chat.PostPayloadTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{Attachment, Card, FileUpload, Markdown, Postable, PostPayload, StreamChunk}

  test "typed post builders preserve posting intent and explicit text fallbacks" do
    markdown = Markdown.root([Markdown.strong("Bold")])
    card = Card.new(%{title: "Card", components: [Card.text("Body")]})

    values = [
      {Postable.text("Text", %{metadata: %{source: "fixture"}}), :text, "Text"},
      {Postable.markdown("**Bold**"), :markdown, "**Bold**"},
      {Postable.markdown(markdown), :markdown, "Bold"},
      {Postable.ast(markdown), :ast, "Bold"},
      {Postable.card(card), :card, "Card\n\nBody"},
      {Postable.card(%{components: ["Body"]}, %{text: "Chosen"}), :card, "Chosen"},
      {Postable.stream(["One", "Two"]), :stream, "OneTwo"}
    ]

    for {postable, kind, text} <- values do
      payload = Postable.to_payload(postable)
      assert payload.kind == kind
      assert Postable.to_text(postable) == text
      assert PostPayload.display_text(payload) == text
      assert Postable.new(postable) == postable
      assert PostPayload.new(payload) == payload
      assert PostPayload.to_map(PostPayload.from_map(PostPayload.to_map(payload))) == PostPayload.to_map(payload)
    end

    assert Postable.to_text(Postable.stream(Stream.map([1], &to_string/1))) == ""
    assert PostPayload.text("Text", %{formatted: "other"}).formatted == "Text"
    assert PostPayload.stream().fallback_text == nil
    assert PostPayload.stream([], %{text: "Explicit", fallback_text: "Fallback"}).formatted == "Fallback"
  end

  test "string kinds and inferred kinds normalize adapter payloads" do
    for {kind, attrs, expected} <- [
          {"text", %{text: "text"}, :text},
          {"markdown", %{markdown: %{nodes: ["bold"]}}, :markdown},
          {"ast", %{ast: %{nodes: ["ast"]}}, :ast},
          {"card", %{card: %{components: ["card"]}}, :card},
          {"stream", %{stream: ["stream"]}, :stream},
          {"unknown", %{text: "text"}, :text}
        ] do
      assert PostPayload.new(Map.put(attrs, "kind", kind)).kind == expected
      assert PostPayload.new(attrs).kind == expected
    end

    assert PostPayload.new(%{markdown: Markdown.new("markdown")}).markdown == "markdown"
    assert_raise Jido.Chat.Errors.Validation, fn -> PostPayload.new(%{raw: %{arbitrary: "value"}}) end
    assert_raise Jido.Chat.Errors.Validation, fn -> PostPayload.new(%{kind: "raw", raw: "value"}) end
  end

  test "invalid AST and card inputs keep readable fallbacks and explicit text wins" do
    invalid = %{root: %{type: :unsupported}, components: [%{kind: :unsupported}], invalid: fn -> :ok end}

    for field <- [:ast, :card], value <- [nil, "literal", invalid, 42] do
      payload = PostPayload.new(%{field => value, :kind => field})

      expected =
        case value do
          nil -> nil
          "literal" -> "literal"
          42 -> "42"
          other -> inspect(other)
        end

      assert PostPayload.display_text(payload) == expected
      assert PostPayload.new(%{field => value, :kind => field, :text => "Explicit"}).text == "Explicit"
    end

    ast = %{root: %{type: :unsupported}}
    payload = PostPayload.new(%{ast: ast})
    assert payload.ast == ast
    assert payload.text == Jason.encode!(ast)
    card = %{components: [%{kind: :unsupported}]}
    assert PostPayload.new(%{card: card}).fallback_text == Jason.encode!(card)
  end

  test "streams retain typed chunks and lazy streams are not evaluated during serialization" do
    chunks = ["Intro", %{kind: :status, payload: "Ready"}, StreamChunk.text("End")]
    payload = PostPayload.stream(chunks, [])
    assert [%StreamChunk{kind: :status}, %StreamChunk{kind: :text}] = tl(payload.stream)
    assert PostPayload.to_map(payload)["stream"] |> Enum.at(1) |> Map.fetch!("__type__") == "stream_chunk"

    lazy = Stream.map(["secret"], fn _ -> flunk("lazy stream was consumed") end)
    payload = PostPayload.stream(lazy, fallback_text: "Pending")
    assert payload.stream == lazy
    assert PostPayload.to_map(payload)["stream"] == nil
    assert PostPayload.display_text(payload) == "Pending"
    assert PostPayload.stream([make_ref()], []).fallback_text == nil
  end

  test "attachment and file upload candidates preserve separate input types" do
    attachment = Attachment.normalize("https://example.test/a.png")
    file = FileUpload.new(%{filename: "notes.txt", data: "bytes"})
    payload = PostPayload.text("Hello", attachments: [attachment], files: [file])
    assert PostPayload.upload_candidates(payload) == [attachment, file]
    assert PostPayload.outbound_attachments(payload) == [attachment, Attachment.normalize(file)]
    assert PostPayload.upload_candidates(%{payload | attachments: nil, files: nil}) == []
    assert PostPayload.outbound_attachments(%{payload | attachments: nil, files: nil}) == []
  end
end
