defmodule Jido.Chat.OptionsLoadOption do
  @moduledoc """
  Provider-neutral option returned by a dynamic select loader.
  """

  alias Jido.Chat.Wire

  @schema Zoi.struct(
            __MODULE__,
            %{
              label: Zoi.string() |> Zoi.min(1),
              value: Zoi.string() |> Zoi.min(1),
              description: Zoi.string() |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the schema for an option-load option."
  def schema, do: @schema

  @doc "Creates an option-load option."
  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = option), do: option
  def new(attrs) when is_map(attrs), do: Jido.Chat.Schema.parse!(__MODULE__, @schema, attrs)

  @doc "Serializes the option."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = option) do
    option
    |> Map.from_struct()
    |> Wire.to_plain()
    |> Map.put("__type__", "options_load_option")
  end

  @doc "Builds an option from serialized data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()
end
