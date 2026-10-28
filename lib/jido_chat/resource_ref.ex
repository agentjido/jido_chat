defmodule Jido.Chat.ResourceRef do
  @moduledoc """
  Portable reference to a provider or host resource.

  A reference contains no credentials and does not perform I/O.
  """

  @kinds [:file, :media, :url]
  @fields [:id, :client_id, :kind, :metadata]
  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string() |> Zoi.min(1),
              client_id: Zoi.string() |> Zoi.min(1),
              kind: Zoi.enum(@kinds),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the portable resource-reference schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates a portable resource reference."
  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = value), do: value |> Map.from_struct() |> new()

  def new(attrs) when is_map(attrs) do
    attrs
    |> Jido.Chat.Value.without_marker()
    |> Jido.Chat.Value.normalize_keys(@fields)
    |> Jido.Chat.Value.normalize_enum(:kind, @kinds)
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Serializes the resource reference to a portable map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value), do: Jido.Chat.Value.plain_struct(new(value), "resource_ref")

  @doc "Restores a resource reference from a portable map."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: new(map)
end
