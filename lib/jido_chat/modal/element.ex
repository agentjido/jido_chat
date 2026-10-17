defmodule Jido.Chat.Modal.Element do
  @moduledoc """
  Canonical modal element used by `Jido.Chat.Modal`.

  Validation enforces portable input rules. Provider length and option-count
  limits belong to each adapter renderer.
  """

  alias Jido.Chat.Wire

  @kinds [
    :text_input,
    :date_input,
    :number_input,
    :select,
    :radio_select,
    :external_select,
    :select_option,
    :option_group
  ]

  @schema Zoi.struct(
            __MODULE__,
            %{
              kind: Zoi.enum(@kinds),
              id: Zoi.string(),
              label: Zoi.string() |> Zoi.nullish(),
              value: Zoi.string() |> Zoi.nullish(),
              placeholder: Zoi.string() |> Zoi.nullish(),
              help_text: Zoi.string() |> Zoi.nullish(),
              fallback_text: Zoi.string() |> Zoi.nullish(),
              required: Zoi.boolean() |> Zoi.default(false),
              multiline: Zoi.boolean() |> Zoi.default(false),
              min_length: Zoi.integer() |> Zoi.nullish(),
              max_length: Zoi.integer() |> Zoi.nullish(),
              min_date: Zoi.string() |> Zoi.nullish(),
              max_date: Zoi.string() |> Zoi.nullish(),
              min_value: Zoi.number() |> Zoi.nullish(),
              max_value: Zoi.number() |> Zoi.nullish(),
              step: Zoi.number() |> Zoi.nullish(),
              options: Zoi.list() |> Zoi.default([]),
              option_groups: Zoi.list() |> Zoi.default([]),
              options_source: Zoi.enum([:static, :external, :dynamic]) |> Zoi.nullish(),
              min_query_length: Zoi.integer() |> Zoi.nullish(),
              timeout_ms: Zoi.integer() |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )
          |> Zoi.refine({__MODULE__, :validate, []})

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
    |> normalize_kind()
    |> normalize_options_source()
    |> normalize_temporal_values()
    |> normalize_options()
    |> normalize_option_groups()
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
    |> Map.update!(:option_groups, fn groups ->
      Enum.map(groups, fn group -> group |> normalize() |> to_map() end)
    end)
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

  defp normalize_kind(attrs), do: normalize_existing_atom_field(attrs, :kind, @kinds)

  defp normalize_options_source(attrs) do
    normalize_existing_atom_field(attrs, :options_source, [:static, :external, :dynamic])
  end

  defp normalize_existing_atom_field(attrs, key, allowed) do
    string_key = Atom.to_string(key)

    case attrs[key] || attrs[string_key] do
      value when is_binary(value) ->
        atom = String.to_existing_atom(value)
        if atom in allowed, do: attrs |> Map.delete(string_key) |> Map.put(key, atom), else: attrs

      _ ->
        attrs
    end
  rescue
    ArgumentError -> attrs
  end

  defp normalize_option_groups(attrs) do
    groups = attrs[:option_groups] || attrs["option_groups"] || []

    attrs
    |> Map.delete("option_groups")
    |> Map.put(:option_groups, Enum.map(groups, &normalize/1))
  end

  defp normalize_temporal_values(attrs) do
    Enum.reduce([:value, :min_date, :max_date], attrs, fn key, acc ->
      string_key = Atom.to_string(key)

      case Map.get(acc, key, Map.get(acc, string_key)) do
        %Date{} = date ->
          acc |> Map.delete(string_key) |> Map.put(key, Date.to_iso8601(date))

        value when key == :value and is_number(value) ->
          acc |> Map.delete(string_key) |> Map.put(key, to_string(value))

        _ ->
          acc
      end
    end)
  end

  @doc false
  def validate(_schema, %__MODULE__{} = element) do
    cond do
      element.min_length != nil and element.min_length < 0 ->
        {:error, "min_length must be zero or greater"}

      element.max_length != nil and element.max_length < 0 ->
        {:error, "max_length must be zero or greater"}

      bounded_above?(element.min_length, element.max_length) ->
        {:error, "min_length must not be greater than max_length"}

      element.min_query_length != nil and element.min_query_length < 0 ->
        {:error, "min_query_length must be zero or greater"}

      element.timeout_ms != nil and element.timeout_ms < 1 ->
        {:error, "timeout_ms must be greater than zero"}

      element.step != nil and element.step <= 0 ->
        {:error, "step must be greater than zero"}

      bounded_above?(element.min_value, element.max_value) ->
        {:error, "min_value must not be greater than max_value"}

      element.kind == :date_input and not valid_date_bounds?(element) ->
        {:error, "date values must use ISO 8601 and min_date must not exceed max_date"}

      element.kind == :number_input and not valid_number_value?(element.value) ->
        {:error, "number input value must be numeric"}

      true ->
        :ok
    end
  end

  defp bounded_above?(nil, _max), do: false
  defp bounded_above?(_min, nil), do: false
  defp bounded_above?(min, max), do: min > max

  defp valid_date_bounds?(element) do
    with {:ok, _value} <- parse_optional_date(element.value),
         {:ok, min_date} <- parse_optional_date(element.min_date),
         {:ok, max_date} <- parse_optional_date(element.max_date) do
      is_nil(min_date) or is_nil(max_date) or Date.compare(min_date, max_date) != :gt
    else
      _ -> false
    end
  end

  defp parse_optional_date(nil), do: {:ok, nil}
  defp parse_optional_date(value), do: Date.from_iso8601(value)

  defp valid_number_value?(nil), do: true

  defp valid_number_value?(value) when is_binary(value) do
    case Float.parse(value) do
      {_number, ""} -> true
      _ -> false
    end
  end

  defp valid_number_value?(_value), do: false
end
