defmodule Jido.Chat.Content do
  @moduledoc """
  One portable chat content part.

  Content can hold text, Markdown, a card, media, a file source, or a tool call
  value. Exactly one value must match the selected kind.
  """

  alias Jido.Chat.{Card, FileSource, Markdown, Media}

  @kinds [:text, :markdown, :card, :media, :file, :tool_use, :tool_result]
  @fields [
    :kind,
    :text,
    :markdown,
    :card,
    :media,
    :file,
    :tool_call_id,
    :tool_name,
    :tool_input,
    :tool_result,
    :tool_error,
    :metadata
  ]
  @schema Zoi.struct(
            __MODULE__,
            %{
              kind: Zoi.enum(@kinds),
              text: Zoi.string() |> Zoi.nullish(),
              markdown: Zoi.any() |> Zoi.nullish(),
              card: Zoi.any() |> Zoi.nullish(),
              media: Zoi.struct(Media) |> Zoi.nullish(),
              file: Zoi.struct(FileSource) |> Zoi.nullish(),
              tool_call_id: Zoi.string() |> Zoi.nullish(),
              tool_name: Zoi.string() |> Zoi.nullish(),
              tool_input: Zoi.map() |> Zoi.nullish(),
              tool_result: Zoi.any() |> Zoi.nullish(),
              tool_error: Zoi.boolean() |> Zoi.default(false),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )
          |> Zoi.refine({__MODULE__, :validate, []})

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the portable content schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates one portable content part."
  @spec new(t() | map() | String.t()) :: t()
  def new(%__MODULE__{} = value), do: value |> Map.from_struct() |> new()
  def new(text) when is_binary(text), do: text(text)

  def new(attrs) when is_map(attrs) do
    attrs
    |> Jido.Chat.Value.without_marker()
    |> Jido.Chat.Value.normalize_keys(@fields)
    |> Jido.Chat.Value.normalize_enum(:kind, @kinds)
    |> normalize_nested()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Creates plain text content."
  @spec text(String.t()) :: t()
  def text(text) when is_binary(text), do: new(%{kind: :text, text: text})

  @doc "Creates Markdown content."
  @spec markdown(Markdown.t() | map() | String.t()) :: t()
  def markdown(value), do: new(%{kind: :markdown, markdown: value})

  @doc "Creates card content."
  @spec card(Card.t() | map()) :: t()
  def card(value), do: new(%{kind: :card, card: value})

  @doc "Creates media content."
  @spec media(Media.t() | map()) :: t()
  def media(value), do: new(%{kind: :media, media: value})

  @doc "Creates file content."
  @spec file(FileSource.t() | map()) :: t()
  def file(value), do: new(%{kind: :file, file: value})

  @doc "Creates tool-use content."
  @spec tool_use(String.t(), String.t(), map()) :: t()
  def tool_use(id, name, input \\ %{}) do
    new(%{kind: :tool_use, tool_call_id: id, tool_name: name, tool_input: input})
  end

  @doc "Creates tool-result content."
  @spec tool_result(String.t(), term(), boolean()) :: t()
  def tool_result(id, result, error? \\ false) do
    new(%{kind: :tool_result, tool_call_id: id, tool_result: result, tool_error: error?})
  end

  @doc "Returns accessible plain text for a content part."
  @spec fallback_text(t()) :: String.t()
  def fallback_text(%__MODULE__{kind: :text, text: text}), do: text
  def fallback_text(%__MODULE__{kind: :markdown, markdown: value}), do: Markdown.plain_text(value)
  def fallback_text(%__MODULE__{kind: :card, card: value}), do: Card.fallback_text(value)
  def fallback_text(%__MODULE__{kind: :media, media: value}), do: value.alt_text || value.caption || value.name || ""
  def fallback_text(%__MODULE__{kind: :file, file: value}), do: value.filename || ""
  def fallback_text(%__MODULE__{kind: :tool_use, tool_name: name}), do: name || ""

  def fallback_text(%__MODULE__{kind: :tool_result, tool_result: result}),
    do: if(is_binary(result), do: result, else: inspect(result))

  @doc "Serializes content to a portable map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    replacements = %{
      markdown: if(value.markdown, do: Markdown.to_map(value.markdown)),
      card: if(value.card, do: Card.to_map(value.card)),
      media: if(value.media, do: Media.to_map(value.media)),
      file: if(value.file, do: FileSource.to_map(value.file))
    }

    Jido.Chat.Value.plain_struct(new(value), "content", replacements)
  end

  @doc "Restores content from a portable map."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: new(map)

  @doc false
  def validate(_schema, %__MODULE__{} = value) do
    case value.kind do
      :text -> required(value.text, "text")
      :markdown -> required(value.markdown, "markdown")
      :card -> required(value.card, "card")
      :media -> required(value.media, "media")
      :file -> required(value.file, "file")
      :tool_use -> required_all([value.tool_call_id, value.tool_name, value.tool_input], "tool use")
      :tool_result -> required_all([value.tool_call_id, value.tool_result], "tool result")
    end
  end

  defp normalize_nested(attrs) do
    attrs
    |> normalize(:markdown, Markdown)
    |> normalize(:card, Card)
    |> normalize(:media, Media)
    |> normalize(:file, FileSource)
  end

  defp normalize(attrs, key, module) do
    case attrs[key] do
      nil ->
        attrs

      %{__struct__: ^module} = value ->
        Map.put(attrs, key, value |> module.to_map() |> module.from_map())

      value when is_map(value) ->
        Map.put(attrs, key, module.from_map(value))

      value when key == :markdown and is_binary(value) ->
        Map.put(attrs, key, value |> Markdown.parse() |> Markdown.to_map() |> Markdown.from_map())

      _ ->
        attrs
    end
  end

  defp required(nil, name), do: {:error, "#{name} is required"}
  defp required("", name), do: {:error, "#{name} is required"}
  defp required(_value, _name), do: :ok

  defp required_all(values, name) do
    if Enum.any?(values, &is_nil/1), do: {:error, "#{name} fields are required"}, else: :ok
  end
end
