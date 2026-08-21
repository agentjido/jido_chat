defmodule Jido.Chat.Card.ChartData do
  @moduledoc """
  One provider-neutral data point in a canonical card chart.
  """

  alias Jido.Chat.Wire

  @schema Zoi.struct(
            __MODULE__,
            %{
              label: Zoi.string() |> Zoi.min(1),
              value: Zoi.number(),
              series: Zoi.string() |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @type input :: t() | map() | {String.t(), number()}

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the schema for chart data."
  def schema, do: @schema

  @doc "Creates a chart data point."
  @spec new(input()) :: t()
  def new(%__MODULE__{} = point), do: point
  def new({label, value}), do: new(%{label: label, value: value})

  def new(attrs) when is_map(attrs) do
    Jido.Chat.Schema.parse!(__MODULE__, @schema, attrs)
  end

  @doc "Serializes the chart data point."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = point) do
    point
    |> Map.from_struct()
    |> Wire.to_plain()
    |> Map.put("__type__", "card_chart_data")
  end

  @doc "Builds chart data from serialized data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()
end
