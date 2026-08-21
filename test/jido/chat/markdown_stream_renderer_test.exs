defmodule Jido.Chat.Markdown.StreamRendererTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Markdown.StreamRenderer
  alias Jido.Chat.StreamChunk
  alias Jido.Chat.StreamMarkdownFixtures

  test "one-character streams flush to the non-streamed Markdown" do
    for {name, markdown} <- StreamMarkdownFixtures.supported_documents() do
      {renderer, updates} =
        markdown
        |> StreamMarkdownFixtures.one_character_chunks()
        |> Enum.reduce({StreamRenderer.new(), []}, fn character, {renderer, updates} ->
          {renderer, update} = StreamRenderer.push(renderer, character)
          {renderer, [update | updates]}
        end)

      assert StreamRenderer.flush(renderer) == markdown, "fixture #{name} changed on flush"
      assert StreamRenderer.render([markdown]) == markdown

      updates
      |> Enum.reject(&is_nil/1)
      |> Enum.each(fn update ->
        assert safe_snapshot?(update), "fixture #{name} emitted unsafe Markdown:\n#{update}"
      end)
    end
  end

  test "partial emphasis, links, and code fences get safe closing syntax" do
    {renderer, emphasis} = StreamRenderer.new() |> StreamRenderer.push("**bold")
    assert String.ends_with?(emphasis, "**")

    {renderer, link} = StreamRenderer.push(renderer, " [guide](https://jido.run")
    assert link =~ "[guide](https://jido.run)"

    {_renderer, fence} = StreamRenderer.push(renderer, "\n\n```elixir\nIO.puts(:ok)")
    assert String.ends_with?(fence, "\n```")

    assert StreamRenderer.render(["**bold"]) == "**bold**"
    assert StreamRenderer.render(["[guide](https://jido.run"]) == "[guide](https://jido.run)"
    assert StreamRenderer.render(["```elixir\n:ok"]) == "```elixir\n:ok\n```"
    assert StreamRenderer.render(["Price * tax and trailing_"]) == "Price * tax and trailing_"
  end

  test "code fence repairs preserve the opening marker and marker length" do
    source = "````markdown\nliteral ``` content\nliteral ~~~ content"
    {renderer, snapshot} = StreamRenderer.new() |> StreamRenderer.push(source)

    assert snapshot == source <> "\n````"

    {_renderer, closed_snapshot} = StreamRenderer.push(renderer, "\n````\n")
    assert closed_snapshot == source <> "\n````\n"

    tilde_source = "~~~~text\nliteral ``` and ~~~ content"
    {_renderer, tilde_snapshot} = StreamRenderer.new() |> StreamRenderer.push(tilde_source)
    assert tilde_snapshot == tilde_source <> "\n~~~~"
  end

  test "a possible table header is buffered until its divider is complete" do
    {renderer, update} = StreamRenderer.new() |> StreamRenderer.push("| Name |  | State |\n")
    assert update == nil

    {renderer, update} = StreamRenderer.push(renderer, "| --- | ---")
    assert update == nil

    {renderer, update} = StreamRenderer.push(renderer, " | --- |\n")
    assert update == "| Name |  | State |\n| --- | --- | --- |\n"

    {renderer, update} = StreamRenderer.push(renderer, "| alpha |  ")
    assert update == nil

    {renderer, update} = StreamRenderer.push(renderer, "| ready |\n")

    assert update ==
             "| Name |  | State |\n| --- | --- | --- |\n| alpha |  | ready |\n"

    assert StreamRenderer.flush(renderer) ==
             "| Name |  | State |\n| --- | --- | --- |\n| alpha |  | ready |\n"
  end

  test "table parsing preserves adjacent empty cells before one optional outer pipe" do
    {renderer, update} = StreamRenderer.new() |> StreamRenderer.push("| Name |||\n")
    assert update == nil

    {renderer, update} = StreamRenderer.push(renderer, "| --- | --- | --- |\n")
    assert update == "| Name |||\n| --- | --- | --- |\n"

    {renderer, update} = StreamRenderer.push(renderer, "| alpha |||\n")
    assert update == "| Name |||\n| --- | --- | --- |\n| alpha |||\n"

    assert StreamRenderer.flush(renderer) ==
             "| Name |||\n| --- | --- | --- |\n| alpha |||\n"
  end

  test "plain one-character pushes preserve final content" do
    renderer =
      Enum.reduce(1..10_000, StreamRenderer.new(), fn _index, renderer ->
        {renderer, _update} = StreamRenderer.push(renderer, "a")
        renderer
      end)

    assert StreamRenderer.flush(renderer) == String.duplicate("a", 10_000)
  end

  test "incremental snapshots preserve leading blank chunks" do
    {renderer, update} = StreamRenderer.new() |> StreamRenderer.push("\n")
    assert update == nil

    {_renderer, update} = StreamRenderer.push(renderer, "visible")
    assert update == "\nvisible"
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

  test "the non-streamed payload fallback uses the same structured renderer" do
    payload =
      Jido.Chat.PostPayload.stream(
        [
          %{kind: :status, text: "Working"},
          %{kind: :plan, payload: ["Inspect", "Change"]}
        ],
        %{}
      )

    assert payload.fallback_text ==
             "\n> **Status:** Working\n\n**Plan**\n\n- Inspect\n- Change\n"
  end

  defp safe_snapshot?(snapshot) do
    String.trim(snapshot) != "" and balanced_fences?(snapshot) and closed_links?(snapshot) and
      balanced_emphasis?(snapshot) and aligned_table?(snapshot)
  end

  defp balanced_fences?(snapshot) do
    snapshot
    |> String.split("\n")
    |> Enum.count(&Regex.match?(~r/^\s*(`{3,}|~{3,})/, &1))
    |> rem(2) == 0
  end

  defp closed_links?(snapshot) do
    labels_closed? = count(snapshot, "[") == count(snapshot, "]")

    destinations_closed? =
      snapshot
      |> String.split("](")
      |> Enum.drop(1)
      |> Enum.all?(&String.contains?(&1, ")"))

    labels_closed? and destinations_closed?
  end

  defp balanced_emphasis?(snapshot) do
    text =
      snapshot
      |> String.replace(~r/```.*?```/s, "")
      |> String.replace(~r/`[^`]*`/, "")
      |> String.replace(~r/\]\([^)]*\)/, "")

    strong_count = count(text, "**")
    single_asterisk_count = text |> String.replace("**", "") |> count("*")
    underscore_count = count(text, "_")

    rem(strong_count, 2) == 0 and rem(single_asterisk_count, 2) == 0 and
      rem(underscore_count, 2) == 0
  end

  defp aligned_table?(snapshot) do
    lines = String.split(snapshot, "\n", trim: true)

    case Enum.find_index(lines, &Regex.match?(~r/^\s*\|?\s*:?-{3,}/, &1)) do
      nil ->
        true

      0 ->
        false

      divider_index ->
        header_cells = table_cell_count(Enum.at(lines, divider_index - 1))

        lines
        |> Enum.drop(divider_index)
        |> Enum.take_while(&String.contains?(&1, "|"))
        |> Enum.all?(&(table_cell_count(&1) == header_cells))
    end
  end

  defp table_cell_count(line) do
    line
    |> String.trim()
    |> String.trim_leading("|")
    |> String.trim_trailing("|")
    |> String.split("|", trim: false)
    |> length()
  end

  defp count(text, pattern), do: length(:binary.matches(text, pattern))
end
