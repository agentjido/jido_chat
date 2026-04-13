defmodule Jido.Chat.PostPayload do
  @moduledoc """
  Typed normalized outbound payload used by thread/channel posting helpers.
  """

  alias Jido.Chat.{Attachment, Card, FileUpload, Markdown, StreamChunk, Wire}

  @schema Zoi.struct(
            __MODULE__,
            %{
              kind:
                Zoi.enum([:text, :markdown, :raw, :ast, :card, :stream])
                |> Zoi.default(:text),
              text: Zoi.string() |> Zoi.nullish(),
              markdown: Zoi.string() |> Zoi.nullish(),
              formatted: Zoi.string() |> Zoi.nullish(),
              raw: Zoi.any() |> Zoi.nullish(),
              ast: Zoi.any() |> Zoi.nullish(),
              card: Zoi.any() |> Zoi.nullish(),
              stream: Zoi.any() |> Zoi.nullish(),
              fallback_text: Zoi.string() |> Zoi.nullish(),
              attachments: Zoi.array(Zoi.struct(Attachment)) |> Zoi.default([]),
              files: Zoi.array(Zoi.struct(FileUpload)) |> Zoi.default([]),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for PostPayload."
  def schema, do: @schema

  @doc "Creates a normalized post payload."
  @spec new(map() | t()) :: t()
  def new(%__MODULE__{} = payload), do: payload

  def new(attrs) when is_map(attrs) do
    attrs
    |> normalize_kind()
    |> normalize_content()
    |> normalize_metadata()
    |> normalize_attachments()
    |> normalize_files()
    |> normalize_stream()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Builds a text payload."
  @spec text(String.t(), keyword() | map()) :: t()
  def text(value, opts \\ []) when is_binary(value) do
    opts = normalize_opts(opts)
    new(Map.merge(opts, %{kind: :text, text: value, formatted: value}))
  end

  @doc "Builds a stream payload marker."
  @spec stream() :: t()
  def stream, do: new(%{kind: :stream})

  @doc "Builds a stream payload from chunk input."
  @spec stream(term(), keyword() | map()) :: t()
  def stream(chunks, opts) do
    opts = normalize_opts(opts)
    new(Map.merge(opts, %{kind: :stream, stream: chunks}))
  end

  @doc "Returns the best text fallback for the payload."
  @spec display_text(t()) :: String.t() | nil
  def display_text(%__MODULE__{} = payload), do: payload.text || payload.fallback_text

  @doc "Returns upload candidates preserving canonical file inputs where present."
  @spec upload_candidates(t()) :: [Attachment.t() | FileUpload.t()]
  def upload_candidates(%__MODULE__{} = payload) do
    (payload.attachments || []) ++ (payload.files || [])
  end

  @doc "Returns outbound attachments including normalized file uploads."
  @spec outbound_attachments(t()) :: [Attachment.t()]
  def outbound_attachments(%__MODULE__{} = payload) do
    attachment_uploads =
      payload.files
      |> Kernel.||([])
      |> Enum.map(&Attachment.normalize/1)

    (payload.attachments || []) ++ attachment_uploads
  end

  @doc "Serializes post payload into plain map with type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = payload) do
    payload
    |> Map.from_struct()
    |> Map.update!(:ast, &serialize_ast/1)
    |> Map.update!(:card, &serialize_card/1)
    |> Map.update!(:stream, &serialize_stream/1)
    |> Wire.to_plain()
    |> Map.put("__type__", "post_payload")
  end

  @doc "Builds post payload from serialized data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()

  defp normalize_kind(attrs) do
    kind =
      attrs
      |> Map.get(:kind, Map.get(attrs, "kind"))
      |> normalize_kind_value()
      |> Kernel.||(infer_kind(attrs))

    Map.put(attrs, :kind, kind)
  end

  defp normalize_content(%{kind: :text} = attrs) do
    text = attrs[:text] || attrs["text"]
    formatted = attrs[:formatted] || attrs["formatted"] || text

    attrs
    |> Map.put(:text, text)
    |> Map.put(:formatted, formatted)
  end

  defp normalize_content(%{kind: :markdown} = attrs) do
    markdown =
      case attrs[:markdown] || attrs["markdown"] || attrs[:text] || attrs["text"] do
        %Markdown{} = markdown -> Markdown.stringify(markdown)
        %{} = markdown -> markdown |> Markdown.new() |> Markdown.stringify()
        value -> value
      end

    text = attrs[:text] || attrs["text"] || markdown
    formatted = attrs[:formatted] || attrs["formatted"] || text

    attrs
    |> Map.put(:markdown, markdown)
    |> Map.put(:text, text)
    |> Map.put(:formatted, formatted)
  end

  defp normalize_content(%{kind: :raw} = attrs) do
    raw = attrs[:raw] || attrs["raw"]
    text = attrs[:text] || attrs["text"] || to_text_value(raw)
    formatted = attrs[:formatted] || attrs["formatted"] || text

    attrs
    |> Map.put(:raw, raw)
    |> Map.put(:text, text)
    |> Map.put(:formatted, formatted)
  end

  defp normalize_content(%{kind: :ast} = attrs) do
    ast = attrs[:ast] || attrs["ast"] || attrs[:raw] || attrs["raw"]
    raw = attrs[:raw] || attrs["raw"] || ast
    fallback_text = attrs[:fallback_text] || attrs["fallback_text"]
    {ast, formatted, ast_text} = normalize_ast(ast)
    text = attrs[:text] || attrs["text"] || fallback_text || ast_text
    formatted = attrs[:formatted] || attrs["formatted"] || formatted || text

    attrs
    |> Map.put(:ast, ast)
    |> Map.put(:raw, raw)
    |> Map.put(:fallback_text, fallback_text)
    |> Map.put(:text, text)
    |> Map.put(:formatted, formatted)
  end

  defp normalize_content(%{kind: :card} = attrs) do
    card = attrs[:card] || attrs["card"] || attrs[:raw] || attrs["raw"]
    {card, raw, card_text} = normalize_card(card)

    fallback_text =
      attrs[:fallback_text] || attrs["fallback_text"] || attrs[:text] || attrs["text"] ||
        card_text

    text = attrs[:text] || attrs["text"] || fallback_text
    formatted = attrs[:formatted] || attrs["formatted"] || text

    attrs
    |> Map.put(:card, card)
    |> Map.put(:raw, raw)
    |> Map.put(:fallback_text, fallback_text)
    |> Map.put(:text, text)
    |> Map.put(:formatted, formatted)
  end

  defp normalize_content(%{kind: :stream} = attrs) do
    stream = attrs[:stream] || attrs["stream"] || attrs[:raw] || attrs["raw"]

    fallback_text =
      attrs[:fallback_text] || attrs["fallback_text"] || attrs[:text] || attrs["text"] ||
        stream_fallback_text(stream)

    formatted = attrs[:formatted] || attrs["formatted"] || fallback_text

    attrs
    |> Map.put(:stream, stream)
    |> Map.put(:fallback_text, fallback_text)
    |> Map.put(:text, attrs[:text] || attrs["text"])
    |> Map.put(:formatted, formatted)
  end

  defp normalize_metadata(attrs) do
    metadata = attrs[:metadata] || attrs["metadata"] || %{}

    metadata =
      case attrs[:kind] do
        :markdown -> Map.put_new(metadata, :format, :markdown)
        :ast -> Map.put_new(metadata, :format, :ast)
        :card -> Map.put_new(metadata, :format, :card)
        _other -> metadata
      end

    attrs
    |> Map.delete("metadata")
    |> Map.put(:metadata, metadata)
  end

  defp normalize_attachments(attrs) do
    attachments = attrs[:attachments] || attrs["attachments"] || []

    attrs
    |> Map.delete("attachments")
    |> Map.put(:attachments, Attachment.normalize_many(attachments))
  end

  defp normalize_files(attrs) do
    files = attrs[:files] || attrs["files"] || []

    attrs
    |> Map.delete("files")
    |> Map.put(:files, FileUpload.normalize_many(files))
  end

  defp normalize_stream(attrs) do
    stream = attrs[:stream] || attrs["stream"]

    normalized =
      case stream do
        chunks when is_list(chunks) -> Enum.map(chunks, &normalize_stream_item/1)
        other -> other
      end

    attrs
    |> Map.delete("stream")
    |> Map.put(:stream, normalized)
  end

  defp infer_kind(attrs) do
    cond do
      present?(attrs[:stream] || attrs["stream"]) -> :stream
      present?(attrs[:card] || attrs["card"]) -> :card
      present?(attrs[:ast] || attrs["ast"]) -> :ast
      present?(attrs[:raw] || attrs["raw"]) -> :raw
      present?(attrs[:markdown] || attrs["markdown"]) -> :markdown
      true -> :text
    end
  end

  defp normalize_kind_value(kind)
       when kind in [:text, :markdown, :raw, :ast, :card, :stream],
       do: kind

  defp normalize_kind_value(kind) when is_binary(kind) do
    case kind do
      "text" -> :text
      "markdown" -> :markdown
      "raw" -> :raw
      "ast" -> :ast
      "card" -> :card
      "stream" -> :stream
      _ -> nil
    end
  end

  defp normalize_kind_value(_kind), do: nil

  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(opts) when is_map(opts), do: opts

  defp normalize_stream_item(%StreamChunk{} = chunk), do: chunk
  defp normalize_stream_item(chunk) when is_map(chunk), do: StreamChunk.new(chunk)
  defp normalize_stream_item(chunk), do: chunk

  defp normalize_ast(%Markdown{} = markdown) do
    {markdown, Markdown.stringify(markdown), Markdown.plain_text(markdown)}
  end

  defp normalize_ast(%{} = ast) do
    markdown = Markdown.new(ast)
    {markdown, Markdown.stringify(markdown), Markdown.plain_text(markdown)}
  rescue
    _ -> {ast, to_text_value(ast), to_text_value(ast)}
  end

  defp normalize_ast(ast), do: {ast, to_text_value(ast), to_text_value(ast)}

  defp normalize_card(%Card{} = card) do
    fallback = Card.fallback_text(card)
    {card, card, fallback}
  end

  defp normalize_card(%{} = card) do
    normalized = Card.new(card)
    fallback = Card.fallback_text(normalized)
    {normalized, normalized, fallback}
  rescue
    _ -> {card, card, to_text_value(card)}
  end

  defp normalize_card(card), do: {card, card, to_text_value(card)}

  defp stream_fallback_text(chunks) when is_list(chunks) do
    chunks
    |> Enum.map(fn
      %StreamChunk{} = chunk -> StreamChunk.fallback_text(chunk)
      value when is_binary(value) -> value
      value when is_map(value) -> value |> StreamChunk.new() |> StreamChunk.fallback_text()
      value -> to_string(value)
    end)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("")
    |> blank_to_nil()
  rescue
    _ -> nil
  end

  defp stream_fallback_text(_), do: nil

  defp serialize_stream(nil), do: nil

  defp serialize_stream(chunks) when is_list(chunks) do
    Enum.map(chunks, fn
      %StreamChunk{} = chunk -> StreamChunk.to_map(chunk)
      other -> Wire.to_plain(other)
    end)
  end

  defp serialize_stream(_other), do: nil

  defp serialize_ast(%Markdown{} = markdown), do: Markdown.to_map(markdown)
  defp serialize_ast(other), do: Wire.to_plain(other)

  defp serialize_card(%Card{} = card), do: Card.to_map(card)
  defp serialize_card(other), do: Wire.to_plain(other)

  defp to_text_value(nil), do: nil
  defp to_text_value(value) when is_binary(value), do: value

  defp to_text_value(value) do
    case Jason.encode(value) do
      {:ok, encoded} -> encoded
      {:error, _reason} -> inspect(value)
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_value), do: true
end
