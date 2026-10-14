defmodule Jido.Chat.OptionsLoadOptionGroup do
  @moduledoc """
  A labeled group of provider-neutral dynamic select options.
  """

  alias Jido.Chat.{OptionsLoadOption, Wire}

  @schema Zoi.struct(
            __MODULE__,
            %{
              label: Zoi.string() |> Zoi.min(1),
              options: Zoi.list() |> Zoi.min(1),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the schema for an option group."
  def schema, do: @schema

  @doc "Creates an option group."
  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = group), do: group

  def new(attrs) when is_map(attrs) do
    options = attrs[:options] || attrs["options"] || []

    attrs
    |> Map.delete("options")
    |> Map.put(:options, Enum.map(options, &OptionsLoadOption.new/1))
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Serializes the option group."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = group) do
    group
    |> Map.from_struct()
    |> Map.update!(:options, &Enum.map(&1, fn option -> OptionsLoadOption.to_map(option) end))
    |> Wire.to_plain()
    |> Map.put("__type__", "options_load_option_group")
  end

  @doc "Builds an option group from serialized data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()
end
