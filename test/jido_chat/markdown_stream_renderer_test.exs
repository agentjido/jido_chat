defmodule Jido.Chat.Markdown.StreamRendererTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Markdown.StreamRenderer
  alias Jido.Chat.StreamChunk
  alias Jido.Chat.StreamMarkdownFixtures

  test "complete documents keep their exact source across one-character chunks" do
    sources =
      Enum.map(StreamMarkdownFixtures.supported_documents(), &elem(&1, 1)) ++
        [
          "`array[`",
          "`x](y`",
          "Before `a_*[` after",
          "```text\n[\n```",
          "~~~~text\n[**literal**\n~~~~",
          "````text\nliteral ``` and [\n````",
          "**Olá 世界 👋**"
        ]

    for source <- sources do
      renderer =
        source
        |> String.codepoints()
        |> Enum.reduce(StreamRenderer.new(), fn character, renderer ->
          {renderer, _update} = StreamRenderer.push(renderer, character)
          renderer
        end)

      assert StreamRenderer.flush(renderer) == source
      assert StreamRenderer.render([source]) == source
      assert html(StreamRenderer.snapshot(renderer)) == html(source)
    end
  end

  test "fragment completion does not become input for the next chunk" do
    {renderer, update} = StreamRenderer.push(StreamRenderer.new(), "**bo")
    assert update == "**bo**"
    assert html(update) == "<p><strong>bo</strong></p>"

    {renderer, update} = StreamRenderer.push(renderer, "ld** x")
    assert update == "**bold** x"
    assert StreamRenderer.snapshot(renderer) == update
    assert StreamRenderer.flush(renderer) == "**bold** x"

    {renderer, nil} = StreamRenderer.push(renderer, "")
    {renderer, nil} = StreamRenderer.push(renderer, %{kind: :data, payload: %{ignored: true}})
    assert StreamRenderer.snapshot(renderer) == update
  end

  test "an incomplete link uses a placeholder until its destination is complete" do
    {renderer, update} = StreamRenderer.push(StreamRenderer.new(), "Read [guide](https://ji")
    assert update == "Read [guide](mdex:incomplete-link)"
    refute update =~ "https://ji"

    {renderer, update} = StreamRenderer.push(renderer, "do.run/docs?q=chat) now.")
    assert update == "Read [guide](https://jido.run/docs?q=chat) now."
    assert StreamRenderer.flush(renderer) == update
  end

  test "code previews close the fence without changing literal Markdown" do
    source = "````markdown\nliteral ``` content\nliteral ~~~ and ** content"
    {renderer, update} = StreamRenderer.push(StreamRenderer.new(), source)
    assert update == source <> "\n````"
    assert html(update) =~ "literal ~~~ and ** content"

    {renderer, nil} = StreamRenderer.push(renderer, "\n````\n")
    assert html(StreamRenderer.snapshot(renderer)) == html(source <> "\n````\n")
    assert StreamRenderer.flush(renderer) == source <> "\n````\n"
  end

  test "MDEx completes table headers and rows while preserving empty cells" do
    {renderer, update} = StreamRenderer.push(StreamRenderer.new(), "| Name |  | State |\n")
    assert html(update) =~ "<table>"
    assert update == "| Name |  | State |\n| --- | --- | --- |"

    {renderer, _update} = StreamRenderer.push(renderer, "| --- | --- | --- |\n| alpha |  ")
    assert StreamRenderer.snapshot(renderer) =~ "| alpha |  |  |"

    {renderer, update} = StreamRenderer.push(renderer, "| ready |\n")
    assert update =~ "| alpha |  | ready |"

    assert StreamRenderer.flush(renderer) ==
             "| Name |  | State |\n| --- | --- | --- |\n| alpha |  | ready |\n"

    source = "| Name |||\n| --- | --- | --- |\n| alpha |||\n"
    {renderer, update} = StreamRenderer.push(StreamRenderer.new(), source)
    assert update =~ "| Name |  |  |"
    assert update =~ "| alpha |  |  |"
    assert StreamRenderer.flush(renderer) == source
  end

  test "strikethrough and task lists use the MDEx extensions" do
    {renderer, update} = StreamRenderer.push(StreamRenderer.new(), "~~old")
    assert html(update) == "<p><del>old</del></p>"

    {_renderer, update} = StreamRenderer.push(renderer, "~~\n\n- [x] done\n- [ ] next")
    assert html(update) =~ "type=\"checkbox\""
    assert html(update) =~ "checked=\"\""
  end

  test "final output preserves whitespace and open syntax instead of preview repairs" do
    for source <- [
          "  first\n\nsecond  \n",
          "**bold",
          "[guide](https://jido.run",
          "```elixir\n:ok",
          "Price * tax and trailing_",
          # MDEx 0.14.2 can add a stray preview backtick for this complete source.
          "````text\nliteral ``` content\n````\n\nDone."
        ] do
      {renderer, _update} = StreamRenderer.push(StreamRenderer.new(), source)
      assert StreamRenderer.flush(renderer) == source
      assert StreamRenderer.render([source]) == source
    end
  end

  test "empty previews are suppressed and buffered chunks remain available" do
    assert StreamRenderer.snapshot(StreamRenderer.new()) == nil
    assert StreamRenderer.flush(StreamRenderer.new()) == nil
    assert StreamRenderer.render(["", " \n\t"]) == nil

    {renderer, nil} = StreamRenderer.push(StreamRenderer.new(), "\n")
    {renderer, "visible"} = StreamRenderer.push(renderer, "visible")
    assert StreamRenderer.flush(renderer) == "\nvisible"

    renderer = StreamRenderer.append(renderer, " **more")
    assert StreamRenderer.snapshot(renderer) == "visible"
    {renderer, "visible **more**"} = StreamRenderer.push(renderer, "")
    assert StreamRenderer.flush(renderer) == "\nvisible **more"
  end

  test "a finite source is consumed once and its resource is closed" do
    owner = self()

    source =
      Stream.resource(
        fn -> ["**bo", "ld**\n"] end,
        fn
          [] ->
            {:halt, []}

          [chunk | rest] ->
            send(owner, {:read, chunk})
            {[chunk], rest}
        end,
        fn _ -> send(owner, :closed) end
      )

    assert StreamRenderer.render(source) == "**bold**\n"
    assert_receive {:read, "**bo"}
    assert_receive {:read, "ld**\n"}
    assert_receive :closed
    refute_receive {:read, _}
  end

  test "structured stream chunks have deterministic Markdown fallbacks" do
    for kind <- [:text, :markdown] do
      text = "  first line\n\nsecond line  \n"
      chunk = StreamChunk.new(%{kind: kind, text: text})

      assert StreamChunk.fallback_text(chunk) == text
      assert StreamChunk.markdown_fallback(chunk) == text
    end

    assert StreamChunk.new(%{kind: :status, text: "Working"}) |> StreamChunk.fallback_text() ==
             "Working"

    assert StreamChunk.new(%{kind: :plan, payload: [%{label: "Inspect"}, "Change"]})
           |> StreamChunk.fallback_text() == "Inspect\nChange"

    assert StreamChunk.new(%{kind: :step_finish, payload: %{label: "Inspect"}})
           |> StreamChunk.fallback_text() == "Inspect"

    assert StreamChunk.new(%{
             kind: :timeline,
             payload: [%{at: "10:00", label: "Started"}, %{label: "Finished"}]
           })
           |> StreamChunk.fallback_text() == "10:00 — Started\nFinished"

    assert StreamChunk.markdown_fallback(%{kind: :status, text: "Working"}) ==
             "\n> **Status:** Working\n"

    assert StreamChunk.markdown_fallback(%{kind: :plan, payload: ["Inspect", "Change"]}) ==
             "\n**Plan**\n\n- Inspect\n- Change\n"

    assert StreamChunk.markdown_fallback(%{kind: :step_start, payload: %{label: "Inspect"}}) ==
             "\n- [ ] Inspect\n"

    assert StreamChunk.markdown_fallback(%{kind: :step_finish, payload: %{label: "Inspect"}}) ==
             "\n- [x] Inspect\n"

    assert StreamChunk.markdown_fallback(%{
             kind: :timeline,
             payload: [%{at: "10:00", label: "Started"}, %{label: "Finished"}]
           }) == "\n**Timeline**\n\n- 10:00 — Started\n- Finished\n"

    assert StreamChunk.markdown_fallback(%{kind: :data, payload: %{tool: "search"}}) == ""

    assert StreamChunk.markdown_fallback(%{kind: :status, text: "Wait *now*\nor later"}) ==
             "\n> **Status:** Wait \\*now\\* or later\n"
  end

  defp html(markdown) do
    MDEx.to_html!(markdown,
      extension: [table: true, strikethrough: true, tasklist: true],
      syntax_highlight: nil
    )
  end
end
