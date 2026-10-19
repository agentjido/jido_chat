defmodule Jido.Chat.Markdown.StreamRenderer do
  @moduledoc """
  Builds Markdown previews from a stream of text or structured chunks.

  `push/2` uses MDEx fragment completion to close open Markdown syntax in a
  replacement preview. MDEx can normalize preview formatting and uses
  `mdex:incomplete-link` until a link destination is complete. Tables,
  strikethrough, and task lists are enabled.

  Only original chunks enter the source buffer. Synthetic closers never become
  input for the next preview. `flush/1` and `render/1` return the exact source,
  including whitespace and any syntax still open at the end of the stream.
  """

  alias Jido.Chat.StreamChunk

  @preview_options [
    auto_close: true,
    extension: [table: true, strikethrough: true, tasklist: true],
    syntax_highlight: nil
  ]

  @type t :: %__MODULE__{parts: [String.t()], snapshot: String.t() | nil}

  defstruct parts: [], snapshot: nil

  @doc "Creates an empty streaming Markdown renderer."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Adds one chunk and returns the preview only when it changes."
  @spec push(t(), term()) :: {t(), String.t() | nil}
  def push(%__MODULE__{} = renderer, chunk) do
    next = append(renderer, chunk)
    snapshot = next |> source() |> preview()
    update = if snapshot == renderer.snapshot, do: nil, else: snapshot
    {%{next | snapshot: snapshot}, update}
  end

  @doc "Adds one chunk without calculating a preview."
  @spec append(t(), term()) :: t()
  def append(%__MODULE__{} = renderer, chunk) do
    case StreamChunk.markdown_fallback(chunk) do
      "" -> renderer
      text -> %{renderer | parts: [text | renderer.parts]}
    end
  end

  @doc "Returns the last calculated replacement preview."
  @spec snapshot(t()) :: String.t() | nil
  def snapshot(%__MODULE__{snapshot: snapshot}), do: snapshot

  @doc "Returns the exact final source, or nil when there is no visible text."
  @spec flush(t()) :: String.t() | nil
  def flush(%__MODULE__{} = renderer), do: renderer |> source() |> visible_text()

  @doc "Collects a finite stream into its exact final Markdown fallback."
  @spec render(Enumerable.t()) :: String.t() | nil
  def render(chunks) do
    chunks
    |> Enum.reduce(new(), &append(&2, &1))
    |> flush()
  end

  defp source(%__MODULE__{parts: parts}) do
    parts |> Enum.reverse() |> IO.iodata_to_binary()
  end

  defp preview(source) do
    case visible_text(source) do
      nil ->
        nil

      text ->
        @preview_options |> MDEx.new() |> MDEx.Document.put_markdown(text) |> MDEx.to_markdown!() |> visible_text()
    end
  end

  defp visible_text(text) do
    if String.trim(text) == "", do: nil, else: text
  end
end
