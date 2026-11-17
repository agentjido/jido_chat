defmodule Jido.Chat.Media do
  @moduledoc "Portable media attached to a Post or Message."

  alias Jido.Chat.FileSource

  @kinds [:image, :audio, :video, :file]
  @fields [
    :kind,
    :source,
    :name,
    :media_type,
    :caption,
    :alt_text,
    :width,
    :height,
    :duration,
    :metadata
  ]
  @schema Jido.Joi.struct(
            __MODULE__,
            %{
              kind: Jido.Joi.enum(@kinds),
              source: Jido.Joi.struct(FileSource),
              name: Jido.Joi.string() |> Jido.Joi.nullable() |> Jido.Joi.optional(),
              media_type: Jido.Joi.string() |> Jido.Joi.nullable() |> Jido.Joi.optional(),
              caption: Jido.Joi.string() |> Jido.Joi.nullable() |> Jido.Joi.optional(),
              alt_text: Jido.Joi.string() |> Jido.Joi.nullable() |> Jido.Joi.optional(),
              width: Jido.Joi.integer() |> Jido.Joi.min(0) |> Jido.Joi.nullable() |> Jido.Joi.optional(),
              height: Jido.Joi.integer() |> Jido.Joi.min(0) |> Jido.Joi.nullable() |> Jido.Joi.optional(),
              duration: Jido.Joi.number() |> Jido.Joi.min(0) |> Jido.Joi.nullable() |> Jido.Joi.optional(),
              metadata: Jido.Joi.map() |> Jido.Joi.default(%{})
            },
            coerce: true
          )
          |> Jido.Joi.refine({Jido.Chat.Wire, :portable, []})

  @type t :: unquote(Jido.Joi.type_spec(@schema))
  @enforce_keys Jido.Joi.enforce_keys(@schema)
  defstruct Jido.Joi.struct_fields(@schema)

  @doc "Returns the portable media schema."
  @spec schema() :: Jido.Joi.schema()
  def schema, do: @schema

  @doc "Creates portable media."
  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = value), do: value |> Map.from_struct() |> new()

  def new(attrs) when is_map(attrs) do
    attrs
    |> Jido.Chat.Value.without_marker()
    |> Jido.Chat.Value.normalize_keys(@fields)
    |> Jido.Chat.Value.normalize_enum(:kind, @kinds)
    |> normalize_source()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Serializes media to a portable map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    Jido.Chat.Value.plain_struct(new(value), "media", %{source: FileSource.to_map(value.source)})
  end

  @doc "Restores media from a portable map."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: new(map)

  defp normalize_source(attrs) do
    case attrs[:source] do
      %FileSource{} = value -> Map.put(attrs, :source, FileSource.new(value))
      value when is_map(value) -> Map.put(attrs, :source, FileSource.new(value))
      _ -> attrs
    end
  end
end
