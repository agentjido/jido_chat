defmodule Jido.Chat.MarkdownParserTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Markdown

  test "whitespace-only lines are consumed as blank lines" do
    assert parse_with_deadline(" \t ").root.children == []
    assert Markdown.stringify(parse_with_deadline("first\n \t \nsecond")) == "first\n\nsecond"
  end

  test "indented code fences consume the opening and closing lines" do
    document = parse_with_deadline(" ```elixir\n:ok\n ```\nafter")
    assert Markdown.stringify(document) == "```elixir\n:ok\n```\n\nafter"
  end

  defp parse_with_deadline(input) do
    task = Task.async(fn -> Markdown.parse(input) end)
    assert {:ok, document} = Task.yield(task, 500) || Task.shutdown(task, :brutal_kill)
    document
  end
end
