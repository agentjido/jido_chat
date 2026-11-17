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
  @schema Jido.Joi.struct(
            __MODULE__,
            %{
              kind: Jido.Joi.enum(@kinds),
              text: Jido.Joi.string() |> Jido.Joi.nullable() |> Jido.Joi.optional(),
              markdown: Jido.Joi.struct(Markdown) |> Jido.Joi.nullable() |> Jido.Joi.optional(),
              card: Jido.Joi.struct(Card) |> Jido.Joi.nullable() |> Jido.Joi.optional(),
              media: Jido.Joi.struct(Media) |> Jido.Joi.nullable() |> Jido.Joi.optional(),
              file: Jido.Joi.struct(FileSource) |> Jido.Joi.nullable() |> Jido.Joi.optional(),
              tool_call_id: Jido.Joi.string() |> Jido.Joi.nullable() |> Jido.Joi.optional(),
              tool_name: Jido.Joi.string() |> Jido.Joi.nullable() |> Jido.Joi.optional(),
              tool_input: Jido.Joi.map() |> Jido.Joi.nullable() |> Jido.Joi.optional(),
              tool_result: Jido.Joi.any() |> Jido.Joi.nullable() |> Jido.Joi.optional(),
              tool_error: Jido.Joi.boolean() |> Jido.Joi.default(false),
              metadata: Jido.Joi.map() |> Jido.Joi.default(%{})
            },
            coerce: true
          )
          |> Jido.Joi.refine({__MODULE__, :validate, []})
          |> Jido.Joi.refine({Jido.Chat.Wire, :portable, []})

  @type t :: unquote(Jido.Joi.type_spec(@schema))
  @enforce_keys Jido.Joi.enforce_keys(@schema)
  defstruct Jido.Joi.struct_fields(@schema)

  @doc "Returns the portable content schema."
  @spec schema() :: Jido.Joi.schema()
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
    with :ok <- required_variant(value),
         :ok <- only_selected_variant(value) do
      :ok
    end
  end

  defp required_variant(%__MODULE__{kind: :text, text: value}), do: required(value, "text")
  defp required_variant(%__MODULE__{kind: :markdown, markdown: value}), do: required(value, "markdown")
  defp required_variant(%__MODULE__{kind: :card, card: value}), do: required(value, "card")
  defp required_variant(%__MODULE__{kind: :media, media: value}), do: required(value, "media")
  defp required_variant(%__MODULE__{kind: :file, file: value}), do: required(value, "file")

  defp required_variant(%__MODULE__{kind: :tool_use} = value),
    do: required_all([value.tool_call_id, value.tool_name, value.tool_input], "tool use")

  defp required_variant(%__MODULE__{kind: :tool_result} = value),
    do: required_all([value.tool_call_id, value.tool_result], "tool result")

  defp only_selected_variant(%__MODULE__{} = value) do
    allowed =
      case value.kind do
        :text -> [:text]
        :markdown -> [:markdown]
        :card -> [:card]
        :media -> [:media]
        :file -> [:file]
        :tool_use -> [:tool_call_id, :tool_name, :tool_input]
        :tool_result -> [:tool_call_id, :tool_result]
      end

    variant_fields = [:text, :markdown, :card, :media, :file, :tool_call_id, :tool_name, :tool_input, :tool_result]
    foreign_value? = Enum.any?(variant_fields -- allowed, &(not is_nil(Map.fetch!(value, &1))))
    foreign_error_flag? = value.kind != :tool_result and value.tool_error

    if foreign_value? or foreign_error_flag?,
      do: {:error, "content contains fields for another kind"},
      else: :ok
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
