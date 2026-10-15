defmodule Jido.Chat.StreamChunkTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.StreamChunk

  test "plain and typed text retain their bytes and survive serialization" do
    chunk = StreamChunk.text("one\ntwo", %{metadata: %{source: "fixture"}})
    assert StreamChunk.new(chunk) == chunk
    assert StreamChunk.normalize(chunk) == chunk

    assert StreamChunk.normalize_many(["raw", %{kind: :markdown, text: "**bold**"}]) ==
             ["raw", StreamChunk.new(%{kind: :markdown, text: "**bold**"})]

    assert StreamChunk.fallback_text(chunk) == "one\ntwo"
    assert StreamChunk.markdown_fallback(%{kind: :markdown, text: "**bold**"}) == "**bold**"
    assert StreamChunk.markdown_fallback(StreamChunk.new(%{kind: :text})) == ""
    assert StreamChunk.markdown_fallback("raw") == "raw"
    assert StreamChunk.fallback_text("raw") == "raw"
    assert StreamChunk.markdown_fallback(12) == "12"
    map = StreamChunk.to_map(chunk)
    assert StreamChunk.to_map(StreamChunk.from_map(map)) == map
    assert Zoi.parse(StreamChunk.schema(), %{kind: :unsupported}) |> elem(0) == :error
  end

  test "status and step chunks use safe plain and escaped Markdown labels" do
    for payload <- [%{label: " Run *one* "}, %{"title" => " Run *one* "}, " Run *one* "] do
      chunk = StreamChunk.new(%{kind: :status, payload: payload})
      assert StreamChunk.fallback_text(chunk) == "Run *one*"
      assert StreamChunk.markdown_fallback(chunk) == "\n> **Status:** Run \\*one\\*\n"
    end

    assert StreamChunk.markdown_fallback(StreamChunk.new(%{kind: :step_start, payload: %{title: "Start"}})) ==
             "\n- [ ] Start\n"

    assert StreamChunk.markdown_fallback(StreamChunk.new(%{kind: :step_finish, payload: %{"label" => "Done"}})) ==
             "\n- [x] Done\n"

    assert StreamChunk.fallback_text(StreamChunk.new(%{kind: :status, text: "  Two\n lines  "})) == "Two lines"
  end

  test "plan chunks preserve list order and normalize map and scalar labels" do
    items = [%{label: "One"}, %{"description" => "Two\n parts"}, 3]

    for payload <- [items, %{steps: items}, %{"items" => items}] do
      chunk = StreamChunk.new(%{kind: :plan, payload: payload})
      assert StreamChunk.fallback_text(chunk) == "One\nTwo parts\n3"
      assert StreamChunk.markdown_fallback(chunk) == "\n**Plan**\n\n- One\n- Two parts\n- 3\n"
    end

    assert StreamChunk.fallback_text(StreamChunk.new(%{kind: :plan, payload: "Single"})) == "Single"

    assert StreamChunk.markdown_fallback(StreamChunk.new(%{kind: :plan, payload: %{"label" => "Single"}})) ==
             "\n> **Plan:** Single\n"
  end

  test "timeline fallbacks retain timestamps and safely flatten labels" do
    events = [%{at: "09:00", title: "Open"}, %{"time" => "", "text" => "Wait"}, "Close"]

    for payload <- [%{events: events}, %{"entries" => events}, events] do
      chunk = StreamChunk.new(%{kind: :timeline, payload: payload})
      assert StreamChunk.fallback_text(chunk) == "09:00 — Open\nWait\nClose"
      assert StreamChunk.markdown_fallback(chunk) == "\n**Timeline**\n\n- 09:00 — Open\n- Wait\n- Close\n"
    end

    assert StreamChunk.markdown_fallback(StreamChunk.new(%{kind: :timeline, payload: %{title: "Event"}})) ==
             "\n> **Timeline:** Event\n"

    unknown = StreamChunk.new(%{kind: :plan, payload: [%{unrecognized: 1}]})
    assert StreamChunk.fallback_text(unknown) == "%{unrecognized: 1}"
  end

  test "empty structured payloads produce no fabricated text or Markdown" do
    for kind <- [:status, :plan, :timeline, :step_start, :step_finish], payload <- [nil, %{}, 42] do
      chunk = StreamChunk.new(%{kind: kind, payload: payload})
      assert StreamChunk.fallback_text(chunk) == ""
      assert StreamChunk.markdown_fallback(chunk) == ""
    end

    assert StreamChunk.markdown_fallback(StreamChunk.new(%{kind: :data, payload: %{label: "private"}})) == ""
    assert StreamChunk.fallback_text(StreamChunk.new(%{kind: :data, payload: %{label: "Public"}})) == "Public"
  end
end
