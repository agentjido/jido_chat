defmodule Jido.Chat.Markdown do
  @moduledoc """
  Canonical Markdown AST and formatting helpers.
  """

  alias Jido.Chat.Markdown.Node
  alias Jido.Chat.Wire

  @schema Zoi.struct(
            __MODULE__,
            %{
              root: Zoi.struct(Node),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @type markdown_node :: Node.t()
  @type node_input :: markdown_node() | map() | String.t()

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the schema for Markdown documents."
  def schema, do: @schema

  @doc "Creates a canonical Markdown document."
  @spec new(t() | map() | String.t() | [node_input()]) :: t()
  def new(%__MODULE__{} = markdown), do: markdown

  def new(value) when is_binary(value), do: parse(value)
  def new(value) when is_list(value), do: root(value)

  def new(attrs) when is_map(attrs) do
    attrs
    |> normalize_root()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Builds a Markdown document with a root node."
  @spec root([node_input()], keyword() | map()) :: t()
  def root(children, opts \\ []) when is_list(children) do
    opts = normalize_opts(opts)

    new(%{
      root: Node.new(%{type: :root, children: children}),
      metadata: opts[:metadata] || opts["metadata"] || %{}
    })
  end

  @doc "Builds a paragraph node."
  @spec paragraph([node_input()] | String.t()) :: markdown_node()
  def paragraph(value), do: Node.new(%{type: :paragraph, children: normalize_children(value)})

  @doc "Builds a text node."
  @spec text(String.t()) :: markdown_node()
  def text(value) when is_binary(value), do: Node.new(%{type: :text, text: value})

  @doc "Builds a strong node."
  @spec strong([node_input()] | String.t()) :: markdown_node()
  def strong(value), do: Node.new(%{type: :strong, children: normalize_children(value)})

  @doc "Builds an emphasis node."
  @spec emphasis([node_input()] | String.t()) :: markdown_node()
  def emphasis(value), do: Node.new(%{type: :emphasis, children: normalize_children(value)})

  @doc "Builds a link node."
  @spec link([node_input()] | String.t(), String.t(), keyword() | map()) :: markdown_node()
  def link(label, url, opts \\ []) when is_binary(url) do
    opts = normalize_opts(opts)

    Node.new(%{
      type: :link,
      url: url,
      children: normalize_children(label),
      metadata: opts[:metadata] || opts["metadata"] || %{}
    })
  end

  @doc "Builds an inline code node."
  @spec code(String.t()) :: markdown_node()
  def code(value) when is_binary(value), do: Node.new(%{type: :code, text: value})

  @doc "Builds a fenced code block node."
  @spec code_block(String.t(), String.t() | nil, keyword() | map()) :: markdown_node()
  def code_block(value, language \\ nil, opts \\ []) when is_binary(value) do
    opts = normalize_opts(opts)

    Node.new(%{
      type: :code_block,
      text: value,
      language: language,
      metadata: opts[:metadata] || opts["metadata"] || %{}
    })
  end

  @doc "Builds a heading node."
  @spec heading(pos_integer(), [node_input()] | String.t()) :: markdown_node()
  def heading(level, value) when is_integer(level) and level >= 1 and level <= 6 do
    Node.new(%{type: :heading, level: level, children: normalize_children(value)})
  end

  @doc "Builds a list node."
  @spec list([node_input()], keyword() | map()) :: markdown_node()
  def list(items, opts \\ []) when is_list(items) do
    opts = normalize_opts(opts)

    children =
      Enum.map(items, fn
        %Node{type: :list_item} = item -> item
        item -> list_item(item)
      end)

    Node.new(%{
      type: :list,
      ordered: opts[:ordered] || opts["ordered"] || false,
      start: opts[:start] || opts["start"],
      children: children,
      metadata: opts[:metadata] || opts["metadata"] || %{}
    })
  end

  @doc "Builds a list item node."
  @spec list_item(node_input() | [node_input()]) :: markdown_node()
  def list_item(value), do: Node.new(%{type: :list_item, children: normalize_children(value)})

  @doc "Builds a blockquote node."
  @spec blockquote([node_input()] | String.t()) :: markdown_node()
  def blockquote(value), do: Node.new(%{type: :blockquote, children: normalize_children(value)})

  @doc "Builds a table node."
  @spec table([node_input()], keyword() | map()) :: markdown_node()
  def table(rows, opts \\ []) when is_list(rows) do
    opts = normalize_opts(opts)

    Node.new(%{
      type: :table,
      children: Enum.map(rows, &normalize_row/1),
      metadata: opts[:metadata] || opts["metadata"] || %{}
    })
  end

  @doc "Builds a table row node."
  @spec row([node_input()]) :: markdown_node()
  def row(cells) when is_list(cells) do
    Node.new(%{type: :table_row, children: Enum.map(cells, &normalize_cell/1)})
  end

  @doc "Builds a table cell node."
  @spec cell([node_input()] | String.t()) :: markdown_node()
  def cell(value), do: Node.new(%{type: :table_cell, children: normalize_children(value)})

  @doc "Builds a divider node."
  @spec divider() :: markdown_node()
  def divider, do: Node.new(%{type: :divider})

  @doc "Parses plain Markdown text into a canonical AST."
  @spec parse(String.t()) :: t()
  def parse(markdown) when is_binary(markdown) do
    markdown
    |> String.split("\n", trim: false)
    |> parse_lines([])
    |> Enum.reverse()
    |> root(metadata: %{source: :parse})
  end

  @doc "Stringifies a Markdown document or node back to Markdown text."
  @spec stringify(t() | markdown_node() | [node_input()] | String.t() | nil) :: String.t()
  def stringify(nil), do: ""
  def stringify(value) when is_binary(value), do: value
  def stringify(%__MODULE__{root: root}), do: render_children(root.children, "\n\n")
  def stringify(%Node{} = node), do: render_node(node)

  def stringify(nodes) when is_list(nodes),
    do: nodes |> Enum.map_join("\n\n", &(&1 |> normalize_node() |> render_node()))

  @doc "Extracts plain text from a Markdown document or node."
  @spec plain_text(t() | markdown_node() | [node_input()] | String.t() | nil) :: String.t()
  def plain_text(nil), do: ""
  def plain_text(value) when is_binary(value), do: value
  def plain_text(%__MODULE__{root: root}), do: render_plain_children(root.children, "\n\n")
  def plain_text(%Node{} = node), do: render_plain_node(node)

  def plain_text(nodes) when is_list(nodes) do
    nodes
    |> Enum.map_join("\n\n", &(&1 |> normalize_node() |> render_plain_node()))
  end

  @doc "Walks and transforms every node in the Markdown AST."
  @spec walk(t() | markdown_node(), (markdown_node() -> markdown_node())) ::
          t() | markdown_node()
  def walk(%__MODULE__{root: root} = markdown, fun) when is_function(fun, 1) do
    %{markdown | root: walk_node(root, fun)}
  end

  def walk(%Node{} = node, fun) when is_function(fun, 1), do: walk_node(node, fun)

  @doc "Renders the first table in a Markdown document, or a given table node, as ASCII."
  @spec table_to_ascii(t() | markdown_node()) :: String.t()
  def table_to_ascii(%__MODULE__{root: root}), do: root |> first_table() |> table_to_ascii()
  def table_to_ascii(nil), do: ""

  def table_to_ascii(%Node{type: :table, children: rows}) do
    rows =
      Enum.map(rows, fn %Node{children: cells} ->
        Enum.map(cells, &(&1 |> render_plain_node() |> String.trim()))
      end)

    widths =
      rows
      |> Enum.zip_with(fn column ->
        column
        |> Enum.map(&String.length/1)
        |> Enum.max(fn -> 0 end)
      end)

    case rows do
      [] ->
        ""

      [header | body] ->
        divider =
          widths
          |> Enum.map_join("-+-", &String.duplicate("-", max(&1, 1)))

        [
          render_ascii_row(header, widths),
          divider
          | Enum.map(body, &render_ascii_row(&1, widths))
        ]
        |> Enum.join("\n")
    end
  end

  def table_to_ascii(%Node{} = node), do: node |> first_table() |> table_to_ascii()

  @doc "Serializes Markdown into a plain map with type markers."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = markdown) do
    markdown
    |> Map.from_struct()
    |> Map.update!(:root, &Node.to_map/1)
    |> Wire.to_plain()
    |> Map.put("__type__", "markdown")
  end

  @doc "Builds Markdown from serialized map data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()

  defp normalize_root(attrs) do
    root =
      case attrs[:root] || attrs["root"] do
        %Node{} = root ->
          root

        %{} = root ->
          Node.new(root)

        nil ->
          children = attrs[:nodes] || attrs["nodes"] || []
          Node.new(%{type: :root, children: children})
      end

    attrs
    |> Map.delete("root")
    |> Map.put(:root, root)
  end

  defp parse_lines([], acc), do: acc

  defp parse_lines(["" | rest], acc), do: parse_lines(rest, acc)

  defp parse_lines([line | rest], acc) do
    cond do
      String.starts_with?(line, "```") ->
        {node, remainder} = parse_code_block(rest, String.trim_leading(line, "```"))
        parse_lines(remainder, [node | acc])

      heading_line?(line) ->
        {level, text} = parse_heading(line)
        parse_lines(rest, [heading(level, text) | acc])

      table_header?(line, rest) ->
        {node, remainder} = parse_table([line | rest])
        parse_lines(remainder, [node | acc])

      list_line?(line) ->
        {node, remainder} = parse_list([line | rest])
        parse_lines(remainder, [node | acc])

      String.starts_with?(String.trim_leading(line), "> ") ->
        {node, remainder} = parse_blockquote([line | rest])
        parse_lines(remainder, [node | acc])

      String.trim(line) == "---" ->
        parse_lines(rest, [divider() | acc])

      true ->
        {node, remainder} = parse_paragraph([line | rest])
        parse_lines(remainder, [node | acc])
    end
  end

  defp parse_code_block(lines, language) do
    {body, remainder} = Enum.split_while(lines, &(not String.starts_with?(&1, "```")))
    remainder = if remainder == [], do: [], else: tl(remainder)
    {code_block(Enum.join(body, "\n"), blank_to_nil(String.trim(language))), remainder}
  end

  defp parse_heading(line) do
    trimmed = String.trim_leading(line)
    marks = trimmed |> String.graphemes() |> Enum.take_while(&(&1 == "#")) |> length()
    {marks, trimmed |> String.trim_leading("#") |> String.trim()}
  end

  defp parse_table([header, _separator | rest]) do
    {rows, remainder} =
      rest
      |> Enum.split_while(fn line -> String.contains?(line, "|") and String.trim(line) != "" end)

    header_row = header |> split_table_row() |> row()
    body_rows = Enum.map(rows, &(&1 |> split_table_row() |> row()))
    {table([header_row | body_rows]), remainder}
  end

  defp parse_list(lines) do
    {items, remainder} = Enum.split_while(lines, &list_line?/1)

    ordered? =
      case items do
        [first | _] -> Regex.match?(~r/^\s*\d+\.\s+/, first)
        _ -> false
      end

    items =
      Enum.map(items, fn line ->
        line
        |> String.trim()
        |> String.replace(~r/^([-*]|\d+\.)\s+/, "")
        |> list_item()
      end)

    {list(items, ordered: ordered?), remainder}
  end

  defp parse_blockquote(lines) do
    {quoted, remainder} =
      Enum.split_while(lines, fn line ->
        trimmed = String.trim_leading(line)
        String.starts_with?(trimmed, "> ")
      end)

    text =
      quoted
      |> Enum.map(fn line -> line |> String.trim_leading() |> String.trim_leading("> ") end)
      |> Enum.join("\n")

    {blockquote([paragraph(text)]), remainder}
  end

  defp parse_paragraph(lines) do
    {paragraph_lines, remainder} =
      Enum.split_while(lines, fn line ->
        trimmed = String.trim(line)

        trimmed != "" and not heading_line?(line) and not list_line?(line) and
          not String.starts_with?(trimmed, "> ") and not String.starts_with?(trimmed, "```") and
          not table_header?(line, remainder_preview(lines, line))
      end)

    text =
      paragraph_lines
      |> Enum.map(&String.trim/1)
      |> Enum.join(" ")

    {paragraph(text), remainder}
  end

  defp render_node(%Node{type: :root, children: children}), do: render_children(children, "\n\n")

  defp render_node(%Node{type: :paragraph, children: children}), do: render_children(children, "")

  defp render_node(%Node{type: :text, text: text}), do: text || ""

  defp render_node(%Node{type: :strong, children: children}),
    do: "**#{render_children(children, "")}**"

  defp render_node(%Node{type: :emphasis, children: children}),
    do: "_#{render_children(children, "")}_"

  defp render_node(%Node{type: :link, url: url, children: children}),
    do: "[#{render_children(children, "")}](#{url})"

  defp render_node(%Node{type: :code, text: text}), do: "`#{text || ""}`"

  defp render_node(%Node{type: :code_block, text: text, language: language}) do
    "```#{language || ""}\n#{text || ""}\n```"
  end

  defp render_node(%Node{type: :heading, level: level, children: children}) do
    "#{String.duplicate("#", level || 1)} #{render_children(children, "")}"
  end

  defp render_node(%Node{type: :list, ordered: ordered?, start: start, children: children}) do
    start = start || 1

    children
    |> Enum.with_index(start)
    |> Enum.map_join("\n", fn {%Node{} = child, index} ->
      marker = if ordered?, do: "#{index}. ", else: "- "
      marker <> render_list_item(child)
    end)
  end

  defp render_node(%Node{type: :list_item} = node), do: render_list_item(node)

  defp render_node(%Node{type: :blockquote, children: children}) do
    children
    |> render_children("\n")
    |> String.split("\n")
    |> Enum.map_join("\n", &("> " <> &1))
  end

  defp render_node(%Node{type: :table} = node), do: render_markdown_table(node)

  defp render_node(%Node{type: :table_row, children: children}) do
    children
    |> Enum.map_join(" | ", &render_plain_node/1)
  end

  defp render_node(%Node{type: :table_cell, children: children}),
    do: render_children(children, "")

  defp render_node(%Node{type: :divider}), do: "---"

  defp render_plain_node(%Node{type: :root, children: children}),
    do: render_plain_children(children, "\n\n")

  defp render_plain_node(%Node{type: :paragraph, children: children}),
    do: render_plain_children(children, "")

  defp render_plain_node(%Node{type: :text, text: text}), do: text || ""

  defp render_plain_node(%Node{type: :strong, children: children}),
    do: render_plain_children(children, "")

  defp render_plain_node(%Node{type: :emphasis, children: children}),
    do: render_plain_children(children, "")

  defp render_plain_node(%Node{type: :link, children: children}),
    do: render_plain_children(children, "")

  defp render_plain_node(%Node{type: :code, text: text}), do: text || ""
  defp render_plain_node(%Node{type: :code_block, text: text}), do: text || ""

  defp render_plain_node(%Node{type: :heading, children: children}),
    do: render_plain_children(children, "")

  defp render_plain_node(%Node{type: :list, children: children}) do
    children
    |> Enum.map_join("\n", &render_plain_node/1)
  end

  defp render_plain_node(%Node{type: :list_item, children: children}),
    do: render_plain_children(children, " ")

  defp render_plain_node(%Node{type: :blockquote, children: children}),
    do: render_plain_children(children, "\n")

  defp render_plain_node(%Node{type: :table} = node), do: table_to_ascii(node)

  defp render_plain_node(%Node{type: :table_row, children: children}) do
    children
    |> Enum.map_join(" | ", &render_plain_node/1)
  end

  defp render_plain_node(%Node{type: :table_cell, children: children}),
    do: render_plain_children(children, "")

  defp render_plain_node(%Node{type: :divider}), do: "---"

  defp render_children(children, separator),
    do: children |> Enum.map_join(separator, &(&1 |> normalize_node() |> render_node()))

  defp render_plain_children(children, separator) do
    children
    |> Enum.map_join(separator, &(&1 |> normalize_node() |> render_plain_node()))
    |> String.trim()
  end

  defp render_list_item(%Node{children: children}) do
    children
    |> Enum.map_join(" ", fn child -> child |> normalize_node() |> render_node() end)
    |> String.replace("\n", "\n  ")
  end

  defp render_markdown_table(%Node{children: []}), do: ""

  defp render_markdown_table(%Node{children: [%Node{} = header | body]}) do
    header_cells = Enum.map(header.children, &render_plain_node/1)
    divider = Enum.map_join(header_cells, " | ", fn _ -> "---" end)

    body_rows =
      Enum.map_join(body, "\n", fn %Node{children: cells} ->
        "| " <> Enum.map_join(cells, " | ", &render_plain_node/1) <> " |"
      end)

    [
      "| " <> Enum.join(header_cells, " | ") <> " |",
      "| " <> divider <> " |",
      body_rows
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp walk_node(%Node{} = node, fun) do
    children = Enum.map(node.children, &walk_node(normalize_node(&1), fun))
    node |> Map.put(:children, children) |> fun.()
  end

  defp first_table(%Node{type: :table} = node), do: node

  defp first_table(%Node{children: children}) do
    Enum.find_value(children, &first_table(normalize_node(&1)))
  end

  defp normalize_node(%Node{} = node), do: node
  defp normalize_node(node), do: Node.normalize(node)

  defp normalize_children(value) when is_binary(value), do: [text(value)]
  defp normalize_children(value) when is_list(value), do: Enum.map(value, &normalize_node/1)
  defp normalize_children(value), do: [normalize_node(value)]

  defp normalize_row(%Node{type: :table_row} = row), do: row
  defp normalize_row(values) when is_list(values), do: row(values)
  defp normalize_row(value), do: row([value])

  defp normalize_cell(%Node{type: :table_cell} = cell), do: cell
  defp normalize_cell(value), do: cell(value)

  defp split_table_row(line) do
    line
    |> String.trim()
    |> String.trim("|")
    |> String.split("|")
    |> Enum.map(&String.trim/1)
  end

  defp render_ascii_row(values, widths) do
    values
    |> Enum.zip(widths)
    |> Enum.map_join(" | ", fn {value, width} -> String.pad_trailing(value, width) end)
  end

  defp heading_line?(line), do: Regex.match?(~r/^\s{0,3}\#{1,6}\s+.+$/, line)

  defp list_line?(line) do
    Regex.match?(~r/^\s*([-*]|\d+\.)\s+.+$/, line)
  end

  defp table_header?(line, [separator | _rest]) do
    String.contains?(line, "|") and Regex.match?(~r/^\s*\|?[\s:-|]+\|?\s*$/, separator)
  end

  defp table_header?(_line, _rest), do: false

  defp remainder_preview(lines, current) do
    case Enum.drop_while(lines, &(&1 != current)) do
      [_current | rest] -> rest
      _ -> []
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(opts) when is_map(opts), do: opts
end
