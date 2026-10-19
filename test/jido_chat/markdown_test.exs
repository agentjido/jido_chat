defmodule Jido.Chat.MarkdownTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Markdown
  alias Jido.Chat.Markdown.Node

  test "node constructors reject heading levels that cannot render" do
    for level <- [-1, 0, 7] do
      assert_raise Jido.Chat.Errors.Validation, fn ->
        Node.new(%{type: :heading, level: level, children: ["Title"]})
      end
    end

    for level <- 1..6 do
      node = Node.new(%{type: :heading, level: level, children: ["Title"]})
      assert Markdown.stringify(node) == String.duplicate("#", level) <> " Title"
      assert Node.from_map(Node.to_map(node)) == node
    end
  end

  test "block parsing preserves headings, lists, quotes, tables and following paragraphs" do
    source =
      "# Report\n\n- First\n- Second\n\n> Quote\n> Next\n\n| Name | Count |\n| --- | --- |\n| Ada | 12 |\n\n---\n\nAfter"

    document = Markdown.parse(source)

    assert Enum.map(document.root.children, & &1.type) ==
             [:heading, :list, :blockquote, :table, :divider, :paragraph]

    assert Markdown.stringify(document) == source

    assert Markdown.plain_text(document) ==
             "Report\n\nFirst\nSecond\n\nQuote\nNext\n\nName | Count\n-----+------\nAda  | 12   \n\n---\n\nAfter"
  end

  test "ordered lists and unclosed fences have deterministic fallbacks" do
    assert Markdown.stringify(Markdown.parse("1. One\n2. Two")) == "1. One\n2. Two"
    assert Markdown.stringify(Markdown.parse("```\nbody")) == "```\nbody\n```"
    assert Markdown.plain_text(Markdown.code_block("body", "text", %{"metadata" => %{source: "fixture"}})) == "body"
  end

  test "inline builders retain formatting while plain text removes its markers" do
    paragraph =
      Markdown.paragraph([
        Markdown.strong("Bold"),
        " ",
        Markdown.emphasis("Soft"),
        " ",
        Markdown.link("Docs", "https://example.test", %{metadata: %{source: "fixture"}}),
        " ",
        Markdown.code("x")
      ])

    assert Markdown.stringify(paragraph) == "**Bold** _Soft_ [Docs](https://example.test) `x`"
    assert Markdown.plain_text(paragraph) == "Bold Soft Docs x"

    assert Markdown.stringify(Markdown.heading(3, paragraph)) ==
             "### **Bold** _Soft_ [Docs](https://example.test) `x`"

    assert Markdown.plain_text(Markdown.heading(3, paragraph)) == "Bold Soft Docs x"
    assert Markdown.stringify(Node.new(%{type: :text})) == ""
    assert Markdown.plain_text(Node.new(%{type: :code})) == ""
  end

  test "list and quote builders preserve nested nodes and list starting index" do
    item = Markdown.list_item([Markdown.paragraph("One"), Markdown.code_block("Two")])
    ordered = Markdown.list([item, "Three"], %{"ordered" => true, "start" => 3})
    assert Markdown.stringify(ordered) == "3. One ```\n  Two\n  ```\n4. Three"
    assert Markdown.plain_text(ordered) == "One Two\nThree"
    assert Markdown.stringify(item) == "One ```\n  Two\n  ```"
    assert Markdown.stringify(Markdown.blockquote(["First", "Second"])) == "> First\n> Second"
    assert Markdown.plain_text(Markdown.blockquote(["First", "Second"])) == "First\nSecond"
  end

  test "table builders accept typed rows, lists and a single cell" do
    table = Markdown.table([Markdown.row([Markdown.cell("Name"), "N"]), ["Ada", "2"], "Total"])
    assert Markdown.stringify(table) == "| Name | N |\n| --- | --- |\n| Ada | 2 |\n| Total |"
    assert Markdown.stringify(Markdown.row(["A", "B"])) == "A | B"
    assert Markdown.plain_text(Markdown.row(["A", "B"])) == "A | B"
    assert Markdown.stringify(Markdown.cell([Markdown.strong("A")])) == "**A**"
    assert Markdown.plain_text(Markdown.cell([Markdown.strong("A")])) == "A"
    assert Markdown.stringify(Markdown.table([])) == ""
    assert Markdown.table_to_ascii(Markdown.table([])) == ""
  end

  test "ASCII tables find nested tables and pad columns by content width" do
    table = Markdown.table([["Name", "N"], ["Ada", "12"]])
    expected = "Name | N \n-----+---\nAda  | 12"
    assert Markdown.table_to_ascii(table) == expected
    assert Markdown.table_to_ascii(Markdown.root(["Intro", Markdown.blockquote([table])])) == expected
    assert Markdown.table_to_ascii(Markdown.paragraph("No table")) == ""
    assert Markdown.table_to_ascii(Markdown.root([])) == ""
  end

  test "ASCII tables preserve every column when rows have different lengths" do
    table = Markdown.table([["Name", "N"], ["Ada", "2"], ["Total"], ["Extra", "3", "Note"]])

    assert Markdown.plain_text(table) ==
             "Name  | N |     \n------+---+-----\nAda   | 2 |     \nTotal |   |     \nExtra | 3 | Note"
  end

  test "walking transforms every nested node and leaves the original document intact" do
    document = Markdown.root([Markdown.paragraph([Markdown.strong("one"), " two"])])

    transform = fn
      %Node{type: :text, text: text} = node -> %{node | text: String.upcase(text)}
      node -> node
    end

    assert Markdown.stringify(Markdown.walk(document, transform)) == "**ONE** TWO"
    assert Markdown.stringify(document) == "**one** two"
    assert Markdown.plain_text(Markdown.walk(Markdown.strong("one"), transform)) == "ONE"
  end

  test "documents and nodes retain content through map serialization" do
    node = Markdown.paragraph([Markdown.link("Docs", "https://example.test"), Markdown.code("x")])
    document = Markdown.new([node])
    map = Markdown.to_map(document)
    assert Markdown.to_map(Markdown.from_map(map)) == map
    assert Markdown.stringify(Markdown.new(document)) == "[Docs](https://example.test)`x`"
    assert Node.to_map(Node.from_map(Node.to_map(node))) == Node.to_map(node)
    assert Node.normalize(nil) == nil
    assert Node.normalize(node) == node
    assert Markdown.stringify(Markdown.new("text")) == "text"
    assert Markdown.stringify(Markdown.new(%{nodes: ["text"]})) == "text"
    assert Markdown.stringify(document.root) == "[Docs](https://example.test)`x`"
    assert Markdown.plain_text(document.root) == "Docsx"
    assert Markdown.stringify([node, "tail"]) == "[Docs](https://example.test)`x`\n\ntail"
    assert Markdown.plain_text([node, "tail"]) == "Docsx\n\ntail"
    assert Markdown.stringify(nil) == ""
    assert Markdown.plain_text(nil) == ""
    assert Markdown.stringify("raw") == "raw"
    assert Markdown.plain_text("raw") == "raw"
    assert Zoi.parse(Markdown.schema(), %{}) |> elem(0) == :error
    assert Zoi.parse(Node.schema(), %{type: :unsupported}) |> elem(0) == :error
  end
end
