defmodule Jido.Chat.Modal.Element do
  @moduledoc """
  Canonical modal element used by `Jido.Chat.Modal`.
  """

  alias Jido.Chat.Wire

  @kinds [:text_input, :select, :radio_select, :select_option]

  @schema Zoi.struct(
            __MODULE__,
            %{
              kind: Zoi.enum(@kinds),
              id: Zoi.string(),
              label: Zoi.string() |> Zoi.nullish(),
              value: Zoi.string() |> Zoi.nullish(),
              placeholder: Zoi.string() |> Zoi.nullish(),
              help_text: Zoi.string() |> Zoi.nullish(),
              required: Zoi.boolean() |> Zoi.default(false),
              multiline: Zoi.boolean() |> Zoi.default(false),
              min_length: Zoi.integer() |> Zoi.nullish(),
              max_length: Zoi.integer() |> Zoi.nullish(),
              options: Zoi.list() |> Zoi.default([]),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @type input :: t() | map()

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the schema for modal elements."
  def schema, do: @schema

  @doc "Creates a canonical modal element."
  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = element), do: element

  def new(attrs) when is_map(attrs) do
    attrs
    |> normalize_options()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Normalizes modal element input."
  @spec normalize(input()) :: t()
  def normalize(%__MODULE__{} = element), do: element
  def normalize(map) when is_map(map), do: new(map)

  @doc "Serializes the modal element into a plain map with a type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = element) do
    element
    |> Map.from_struct()
    |> Map.update!(:options, &Enum.map(&1, fn option -> option |> normalize() |> to_map() end))
    |> Wire.to_plain()
    |> Map.put("__type__", "modal_element")
  end

  @doc "Builds a modal element from serialized data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()

  defp normalize_options(attrs) do
    options = attrs[:options] || attrs["options"] || []
    attrs |> Map.delete("options") |> Map.put(:options, Enum.map(options, &normalize/1))
  end
end
