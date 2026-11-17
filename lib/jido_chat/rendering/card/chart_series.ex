defmodule Jido.Chat.Card.ChartSeries do
  @moduledoc """
  One named series whose ordered values align with chart categories.
  """

  alias Jido.Chat.Wire

  @schema Jido.Joi.struct(
            __MODULE__,
            %{
              name: Jido.Joi.string() |> Jido.Joi.min(1),
              values: Jido.Joi.list() |> Jido.Joi.min(1),
              metadata: Jido.Joi.map() |> Jido.Joi.default(%{})
            },
            coerce: true
          )
          |> Jido.Joi.refine({__MODULE__, :validate, []})
          |> Jido.Joi.refine({Jido.Chat.Wire, :portable, []})

  @type t :: unquote(Jido.Joi.type_spec(@schema))

  @enforce_keys Jido.Joi.enforce_keys(@schema)
  defstruct Jido.Joi.struct_fields(@schema)

  @doc "Returns the schema for a chart series."
  def schema, do: @schema

  @doc "Creates a named chart series."
  @spec new(t() | map() | {String.t(), [number()]}) :: t()
  def new(%__MODULE__{} = series), do: series |> Map.from_struct() |> new()
  def new({name, values}), do: new(%{name: name, values: values})

  def new(attrs) when is_map(attrs) do
    attrs
    |> Jido.Chat.Value.without_marker()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

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
  def from_map(map) when is_map(map), do: map |> Jido.Chat.Value.without_marker() |> new()
end
