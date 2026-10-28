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
  @schema Zoi.struct(
            __MODULE__,
            %{
              kind: Zoi.enum(@kinds),
              source: Zoi.struct(FileSource),
              name: Zoi.string() |> Zoi.nullish(),
              media_type: Zoi.string() |> Zoi.nullish(),
              caption: Zoi.string() |> Zoi.nullish(),
              alt_text: Zoi.string() |> Zoi.nullish(),
              width: Zoi.integer() |> Zoi.min(0) |> Zoi.nullish(),
              height: Zoi.integer() |> Zoi.min(0) |> Zoi.nullish(),
              duration: Zoi.number() |> Zoi.min(0) |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the portable media schema."
  @spec schema() :: Zoi.schema()
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
