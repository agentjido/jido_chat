defmodule Jido.Chat.Markdown.StreamRenderer do
  @moduledoc """
  Builds safe Markdown snapshots from an incremental, provider-independent stream.

  The renderer keeps the original text. `push/2` can return a repaired snapshot for
  an in-progress edit. `flush/1` returns stable final Markdown and keeps complete,
  supported Markdown exact. Possible table headers and partial table rows are held
  until their structure is known.
  """

  alias Jido.Chat.StreamChunk

  @type t :: %__MODULE__{
          parts: [iodata()],
          snapshot: String.t() | nil,
          exact_snapshot?: boolean()
        }

  defstruct parts: [],
            snapshot: nil,
            exact_snapshot?: true

  @doc "Creates an empty streaming Markdown renderer."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Adds one text or structured stream chunk and returns a changed safe snapshot."
  @spec push(t(), term()) :: {t(), String.t() | nil}
  def push(%__MODULE__{} = renderer, chunk) do
    text = StreamChunk.markdown_fallback(chunk)

    if incremental_exact_append?(renderer, text) do
      push_exact_text(renderer, text)
    else
      push_with_full_scan(renderer, text)
    end
  end

  @doc "Adds one chunk without calculating a partial snapshot."
  @spec append(t(), term()) :: t()
  def append(%__MODULE__{} = renderer, chunk) do
    %{
      renderer
      | parts: [StreamChunk.markdown_fallback(chunk) | renderer.parts],
        exact_snapshot?: false
    }
  end

  @doc "Returns the current safe replacement snapshot without changing state."
  @spec snapshot(t()) :: String.t() | nil
  def snapshot(%__MODULE__{snapshot: snapshot}), do: snapshot

  @doc "Returns stable final Markdown, or nil when there is no visible text."
  @spec flush(t()) :: String.t() | nil
  def flush(%__MODULE__{} = renderer), do: renderer |> source() |> render_snapshot(:final)

  @doc "Renders a finite stream to its exact final Markdown fallback."
  @spec render(Enumerable.t()) :: String.t() | nil
  def render(chunks) do
    chunks
    |> Enum.reduce(new(), &append(&2, &1))
    |> flush()
  end

  defp incremental_exact_append?(%__MODULE__{} = renderer, text) do
    renderer.exact_snapshot? and plain_text_chunk?(text)
  end

  defp plain_text_chunk?(text) do
    not String.contains?(text, ["\\", "`", "~", "*", "_", "[", "]", "(", ")", "|", "\n", "\r"])
  end

  defp push_exact_text(%__MODULE__{} = renderer, text) do
    snapshot = exact_snapshot(renderer.snapshot, text)
    update = if snapshot == renderer.snapshot, do: nil, else: snapshot

    next = %{
      renderer
      | parts: [text | renderer.parts],
        snapshot: snapshot,
        exact_snapshot?: is_binary(snapshot) or text == ""
    }

    {next, update}
  end

  defp exact_snapshot(nil, text), do: visible_text(text)
  defp exact_snapshot(snapshot, text), do: snapshot <> text

  defp push_with_full_scan(%__MODULE__{} = renderer, text) do
    renderer = %{renderer | parts: [text | renderer.parts]}
    source = source(renderer)
    snapshot = render_snapshot(source, :partial)
    update = if snapshot == renderer.snapshot, do: nil, else: snapshot

    next = %{
      renderer
      | snapshot: snapshot,
        exact_snapshot?: snapshot == source or (is_nil(snapshot) and source == "")
    }

    {next, update}
  end

  defp source(%__MODULE__{parts: parts}) do
    parts |> Enum.reverse() |> IO.iodata_to_binary()
  end

  defp render_snapshot(source, :partial) do
    source
    |> buffer_partial_table()
    |> visible_text()
    |> repair_markdown(:partial)
  end

  defp render_snapshot(source, :final), do: source |> visible_text() |> repair_markdown(:final)

  defp visible_text(text) when is_binary(text) do
    if String.trim(text) == "", do: nil, else: text
  end

  defp repair_markdown(nil, _phase), do: nil

  defp repair_markdown(text, phase) do
    text = buffer_trailing_emphasis_delimiter(text, phase)

    case visible_text(text) do
      nil ->
        nil

      text ->
        case open_fence(text) do
          nil -> repair_inline_markdown(text)
          fence -> text <> newline_before_closer(text) <> fence
        end
    end
  end

  defp buffer_trailing_emphasis_delimiter(text, phase) do
    cond do
      String.ends_with?(text, "\\*") or String.ends_with?(text, "\\_") ->
        text

      String.ends_with?(text, "**") ->
        maybe_buffer_delimiter(text, "**", phase)

      String.ends_with?(text, "__") ->
        maybe_buffer_delimiter(text, "__", phase)

      String.ends_with?(text, "*") and not String.ends_with?(text, "**") ->
        maybe_buffer_delimiter(text, "*", phase)

      String.ends_with?(text, "_") and not String.ends_with?(text, "__") ->
        maybe_buffer_delimiter(text, "_", phase)

      true ->
        text
    end
  end

  defp maybe_buffer_delimiter(text, delimiter, phase) do
    prefix = String.slice(text, 0, String.length(text) - String.length(delimiter))

    if phase == :partial or unclosed_delimiter?(prefix, delimiter) do
      prefix
    else
      text
    end
  end

  defp unclosed_delimiter?(text, delimiter) do
    text
    |> emphasis_stack()
    |> Enum.any?(&String.contains?(&1, delimiter))
  end

  defp repair_inline_markdown(text) do
    if odd_inline_backticks?(text) do
      text <> "`"
    else
      text
      |> close_partial_link()
      |> close_partial_emphasis()
    end
  end

  defp open_fence(text) do
    text
    |> String.split("\n", trim: false)
    |> Enum.reduce(nil, fn line, open -> next_fence_state(line, open) end)
  end

  defp next_fence_state(line, nil), do: opening_fence(line)

  defp next_fence_state(line, marker) do
    if closing_fence?(line, marker), do: nil, else: marker
  end

  defp opening_fence(line) do
    case Regex.run(~r/^ {0,3}(`{3,}|~{3,})/, line, capture: :all_but_first) do
      [marker] -> marker
      _other -> nil
    end
  end

  defp closing_fence?(line, open_marker) do
    case Regex.run(~r/^ {0,3}(`{3,}|~{3,})(.*)$/, line, capture: :all_but_first) do
      [marker, suffix] ->
        String.first(marker) == String.first(open_marker) and
          byte_size(marker) >= byte_size(open_marker) and String.trim(suffix) == ""

      _other ->
        false
    end
  end

  defp newline_before_closer(text) do
    if String.ends_with?(text, "\n"), do: "", else: "\n"
  end

  defp odd_inline_backticks?(text) do
    ~r/(?<!\\)`(?!``)/
    |> Regex.scan(text)
    |> length()
    |> rem(2) == 1
  end

  defp close_partial_link(text) do
    cond do
      unmatched_link_destination?(text) -> text <> ")"
      unmatched_link_label?(text) -> text <> "]()"
      true -> text
    end
  end

  defp unmatched_link_destination?(text) do
    case :binary.matches(text, "](") do
      [] ->
        false

      matches ->
        {position, _length} = List.last(matches)
        suffix = binary_part(text, position + 2, byte_size(text) - position - 2)
        count_character(suffix, "(") >= count_character(suffix, ")")
    end
  end

  defp unmatched_link_label?(text) do
    opens = count_unescaped(text, "[")
    closes = count_unescaped(text, "]")
    opens > closes
  end

  defp close_partial_emphasis(text) do
    scan_text =
      ~r/`[^`]*`/
      |> Regex.replace(text, "")
      |> then(&Regex.replace(~r/\]\([^)]*\)/, &1, ""))

    text <> Enum.join(emphasis_stack(scan_text), "")
  end

  defp emphasis_stack(text) do
    ~r/(?<!\\)(\*\*|__|\*|_)/
    |> Regex.scan(text, capture: :all_but_first, return: :index)
    |> List.flatten()
    |> Enum.reduce([], fn {position, length}, stack ->
      delimiter = binary_part(text, position, length)
      previous = previous_grapheme(text, position)
      following = following_grapheme(text, position + length)
      {can_open?, can_close?} = delimiter_flanking(delimiter, previous, following)

      case stack do
        [^delimiter | rest] when can_close? -> rest
        _other when can_open? -> [delimiter | stack]
        _other -> stack
      end
    end)
  end

  defp delimiter_flanking(delimiter, previous, following) do
    can_open? = not is_nil(following) and not whitespace?(following)
    can_close? = not is_nil(previous) and not whitespace?(previous)

    if delimiter in ["_", "__"] and alphanumeric?(previous) and alphanumeric?(following) do
      {false, false}
    else
      {can_open?, can_close?}
    end
  end

  defp previous_grapheme(_text, 0), do: nil
  defp previous_grapheme(text, position), do: text |> binary_part(0, position) |> String.last()

  defp following_grapheme(text, position) when position >= byte_size(text), do: nil

  defp following_grapheme(text, position) do
    text |> binary_part(position, byte_size(text) - position) |> String.first()
  end

  defp whitespace?(grapheme), do: Regex.match?(~r/^\s$/u, grapheme)
  defp alphanumeric?(nil), do: false
  defp alphanumeric?(grapheme), do: Regex.match?(~r/^[\p{L}\p{N}]$/u, grapheme)

  defp count_unescaped(text, character) do
    text
    |> String.codepoints()
    |> Enum.reduce({0, false}, fn
      "\\", {count, escaped?} -> {count, not escaped?}
      _value, {count, true} -> {count, false}
      ^character, {count, false} -> {count + 1, false}
      _value, {count, false} -> {count, false}
    end)
    |> elem(0)
  end

  defp count_character(text, character) do
    text
    |> String.codepoints()
    |> Enum.count(&(&1 == character))
  end

  defp buffer_partial_table(text) do
    lines = String.split(text, "\n", trim: false)

    case partial_table_start(lines) || partial_table_row(lines) do
      nil -> text
      index -> buffered_prefix(lines, index)
    end
  end

  defp buffered_prefix(_lines, 0), do: ""

  defp buffered_prefix(lines, index) do
    lines |> Enum.take(index) |> Enum.join("\n") |> Kernel.<>("\n")
  end

  defp partial_table_start(lines) do
    count = length(lines)

    cond do
      count >= 2 and possible_table_header?(Enum.at(lines, count - 2)) and
        not table_divider_before?(lines, count - 2) and
        not complete_table_divider?(
          Enum.at(lines, count - 1),
          table_cell_count(Enum.at(lines, count - 2))
        ) and table_divider_prefix?(Enum.at(lines, count - 1)) ->
        count - 2

      count >= 1 and possible_table_header?(List.last(lines)) and
          not confirmed_table_divider_before?(lines, count - 1) ->
        count - 1

      true ->
        nil
    end
  end

  defp partial_table_row(lines) do
    last_index = length(lines) - 1
    last_line = List.last(lines)

    if last_line != "" and String.contains?(last_line, "|") and
         table_divider_before?(lines, last_index) do
      last_index
    end
  end

  defp confirmed_table_divider_before?(lines, index) when index >= 2 do
    header = Enum.at(lines, index - 2)
    divider = Enum.at(lines, index - 1)
    possible_table_header?(header) and complete_table_divider?(divider, table_cell_count(header))
  end

  defp confirmed_table_divider_before?(_lines, _index), do: false

  defp table_divider_before?(lines, before_index) do
    if before_index >= 2 do
      lines
      |> Enum.take(before_index)
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.any?(fn [header, divider] ->
        possible_table_header?(header) and
          complete_table_divider?(divider, table_cell_count(header))
      end)
    else
      false
    end
  end

  defp possible_table_header?(line) do
    String.contains?(line, "|") and not table_divider_line?(line)
  end

  defp table_divider_prefix?(line), do: Regex.match?(~r/^\s*[|:\- ]*$/, line)

  defp complete_table_divider?(line, expected_cells) do
    cells = table_cells(line)

    expected_cells > 0 and length(cells) == expected_cells and
      Enum.all?(cells, &Regex.match?(~r/^:?-{3,}:?$/, String.trim(&1)))
  end

  defp table_divider_line?(line) do
    cells = table_cells(line)
    cells != [] and Enum.all?(cells, &Regex.match?(~r/^:?-{3,}:?$/, String.trim(&1)))
  end

  defp table_cell_count(line), do: line |> table_cells() |> length()

  defp table_cells(line) do
    line
    |> String.trim()
    |> remove_optional_leading_pipe()
    |> remove_optional_trailing_pipe()
    |> String.split("|", trim: false)
  end

  defp remove_optional_leading_pipe("|" <> rest), do: rest
  defp remove_optional_leading_pipe(line), do: line

  defp remove_optional_trailing_pipe(line) do
    if String.ends_with?(line, "|") do
      binary_part(line, 0, byte_size(line) - 1)
    else
      line
    end
  end
end
