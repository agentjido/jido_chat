defmodule Jido.Chat.FileSource do
  @moduledoc """
  Portable input for a file or media operation.

  A source is one provider reference, URL, or base64 value. The value contains
  no local file handle or process reference.
  """

  alias Jido.Chat.ResourceRef

  @kinds [:reference, :url, :base64]
  @fields [:kind, :reference, :url, :content_base64, :filename, :media_type, :metadata]
  @schema Zoi.struct(
            __MODULE__,
            %{
              kind: Zoi.enum(@kinds),
              reference: Zoi.struct(ResourceRef) |> Zoi.nullish(),
              url: Zoi.string() |> Zoi.nullish(),
              content_base64: Zoi.string() |> Zoi.nullish(),
              filename: Zoi.string() |> Zoi.nullish(),
              media_type: Zoi.string() |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )
          |> Zoi.refine({__MODULE__, :validate, []})

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the portable file-source schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates a portable file source."
  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = value), do: value |> Map.from_struct() |> new()

  def new(attrs) when is_map(attrs) do
    attrs
    |> Jido.Chat.Value.without_marker()
    |> Jido.Chat.Value.normalize_keys(@fields)
    |> Jido.Chat.Value.normalize_enum(:kind, @kinds)
    |> normalize_reference()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Creates a source from a provider resource reference."
  @spec reference(ResourceRef.t() | map(), keyword()) :: t()
  def reference(reference, opts \\ []) do
    new(%{kind: :reference, reference: reference, filename: opts[:filename], media_type: opts[:media_type]})
  end

  @doc "Creates a source from a URL."
  @spec url(String.t(), keyword()) :: t()
  def url(url, opts \\ []) do
    new(%{kind: :url, url: url, filename: opts[:filename], media_type: opts[:media_type]})
  end

  @doc "Creates a source from base64 content."
  @spec base64(String.t(), String.t(), keyword()) :: t()
  def base64(content, filename, opts \\ []) do
    new(%{
      kind: :base64,
      content_base64: content,
      filename: filename,
      media_type: opts[:media_type]
    })
  end

  @doc "Serializes the file source to a portable map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    reference = if value.reference, do: ResourceRef.to_map(value.reference)
    Jido.Chat.Value.plain_struct(new(value), "file_source", %{reference: reference})
  end

  @doc "Restores a file source from a portable map."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: new(map)

  @doc false
  def validate(_schema, %__MODULE__{} = value) do
    selected = Enum.count([value.reference, value.url, value.content_base64], &(!is_nil(&1)))

    cond do
      selected != 1 ->
        {:error, "expected exactly one file source"}

      value.kind == :reference and is_nil(value.reference) ->
        {:error, "reference source is required"}

      value.kind == :url and blank?(value.url) ->
        {:error, "url source is required"}

      value.kind == :base64 and (blank?(value.content_base64) or blank?(value.filename)) ->
        {:error, "base64 content and filename are required"}

      value.kind == :base64 and not valid_base64?(value.content_base64) ->
        {:error, "expected valid non-empty base64 content"}

      true ->
        :ok
    end
  end

  defp normalize_reference(attrs) do
    case attrs[:reference] do
      nil -> attrs
      %ResourceRef{} = value -> Map.put(attrs, :reference, ResourceRef.new(value))
      value when is_map(value) -> Map.put(attrs, :reference, ResourceRef.new(value))
    end
  end

  defp valid_base64?(value) do
    case Base.decode64(value) do
      {:ok, bytes} -> byte_size(bytes) > 0
      :error -> false
    end
  end

  defp blank?(value), do: not (is_binary(value) and value != "")
end
