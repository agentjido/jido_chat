defmodule Jido.Chat.OptionsLoadResult do
  @moduledoc """
  Successful, typed output from a dynamic select option loader.

  The core does not set a provider maximum for option or group counts. An
  adapter can apply its own limits before it renders this result.
  """

  alias Jido.Chat.{OptionsLoadOption, OptionsLoadOptionGroup, Wire}

  @schema Zoi.struct(
            __MODULE__,
            %{
              options: Zoi.list() |> Zoi.default([]),
              option_groups: Zoi.list() |> Zoi.default([]),
              has_more: Zoi.boolean() |> Zoi.default(false),
              cursor: Zoi.string() |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the schema for options-load output."
  def schema, do: @schema

  @doc "Creates successful options-load output."
  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = result), do: result

  def new(attrs) when is_map(attrs) do
    options = attrs[:options] || attrs["options"] || []
    groups = attrs[:option_groups] || attrs["option_groups"] || attrs[:groups] || attrs["groups"] || []

    attrs
    |> Map.delete("options")
    |> Map.delete("option_groups")
    |> Map.delete(:groups)
    |> Map.delete("groups")
    |> Map.put(:options, Enum.map(options, &OptionsLoadOption.new/1))
    |> Map.put(:option_groups, Enum.map(groups, &OptionsLoadOptionGroup.new/1))
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Builds output from an option list."
  @spec ok([OptionsLoadOption.t() | map()], keyword() | map()) :: t()
  def ok(options, opts \\ []) when is_list(options) do
    opts = Map.new(opts)
    new(Map.put(opts, :options, options))
  end

  @doc "Serializes options-load output."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = result) do
    result
    |> Map.from_struct()
    |> Map.update!(:options, &Enum.map(&1, fn option -> OptionsLoadOption.to_map(option) end))
    |> Map.update!(:option_groups, fn groups ->
      Enum.map(groups, fn group -> OptionsLoadOptionGroup.to_map(group) end)
    end)
    |> Wire.to_plain()
    |> Map.put("__type__", "options_load_result")
  end

  @doc "Builds options-load output from serialized data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()
end
