defmodule Jido.Chat.Card.ChartSeries do
  @moduledoc """
  One named series whose ordered values align with chart categories.
  """

  alias Jido.Chat.Wire

  @schema Zoi.struct(
            __MODULE__,
            %{
              name: Zoi.string() |> Zoi.min(1),
              values: Zoi.list() |> Zoi.min(1),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )
          |> Zoi.refine({__MODULE__, :validate, []})

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the schema for a chart series."
  def schema, do: @schema

  @doc "Creates a named chart series."
  @spec new(t() | map() | {String.t(), [number()]}) :: t()
  def new(%__MODULE__{} = series), do: series
  def new({name, values}), do: new(%{name: name, values: values})
  def new(attrs) when is_map(attrs), do: Jido.Chat.Schema.parse!(__MODULE__, @schema, attrs)

  @doc false
  def validate(_schema, %__MODULE__{values: values}) do
    if Enum.all?(values, &is_number/1), do: :ok, else: {:error, "series values must be numeric"}
  end

  @doc "Serializes the chart series."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = series) do
    series
    |> Map.from_struct()
    |> Wire.to_plain()
    |> Map.put("__type__", "card_chart_series")
  end

  @doc "Builds a chart series from serialized data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()
end
