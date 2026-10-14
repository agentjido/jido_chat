defmodule Jido.Chat.Card.Component do
  @moduledoc """
  Canonical card component used by `Jido.Chat.Card`.

  Validation enforces portable semantic limits, such as positive page sizes.
  Provider count and text limits belong to each adapter renderer.
  """

  alias Jido.Chat.Markdown
  alias Jido.Chat.Wire
  alias Jido.Chat.Card.{ChartData, ChartSeries}

  @kinds [
    :text,
    :section,
    :fields,
    :field,
    :button,
    :link_button,
    :link,
    :actions,
    :select,
    :select_option,
    :radio_select,
    :external_select,
    :table,
    :pie_chart,
    :bar_chart,
    :area_chart,
    :line_chart,
    :option_group,
    :image,
    :divider
  ]

  @schema Zoi.struct(
            __MODULE__,
            %{
              kind: Zoi.enum(@kinds),
              id: Zoi.string() |> Zoi.nullish(),
              title: Zoi.string() |> Zoi.nullish(),
              label: Zoi.string() |> Zoi.nullish(),
              text: Zoi.string() |> Zoi.nullish(),
              url: Zoi.string() |> Zoi.nullish(),
              value: Zoi.string() |> Zoi.nullish(),
              image_url: Zoi.string() |> Zoi.nullish(),
              alt_text: Zoi.string() |> Zoi.nullish(),
              fallback_text: Zoi.string() |> Zoi.nullish(),
              caption: Zoi.string() |> Zoi.nullish(),
              style: Zoi.string() |> Zoi.nullish(),
              disabled: Zoi.boolean() |> Zoi.default(false),
              markdown: Zoi.any() |> Zoi.nullish(),
              items: Zoi.list() |> Zoi.default([]),
              options: Zoi.list() |> Zoi.default([]),
              option_groups: Zoi.list() |> Zoi.default([]),
              options_source: Zoi.enum([:static, :external, :dynamic]) |> Zoi.nullish(),
              min_query_length: Zoi.integer() |> Zoi.nullish(),
              timeout_ms: Zoi.integer() |> Zoi.nullish(),
              columns: Zoi.list() |> Zoi.default([]),
              rows: Zoi.list() |> Zoi.default([]),
              page_size: Zoi.integer() |> Zoi.nullish(),
              data: Zoi.list() |> Zoi.default([]),
              categories: Zoi.list() |> Zoi.default([]),
              series: Zoi.list() |> Zoi.default([]),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )
          |> Zoi.refine({__MODULE__, :validate, []})

  @type t :: unquote(Zoi.type_spec(@schema))
  @type input :: t() | map() | String.t()

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the schema for a card component."
  def schema, do: @schema

  @doc "Creates a canonical card component."
  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = component), do: component

  def new(attrs) when is_map(attrs) do
    attrs
    |> normalize_kind()
    |> normalize_options_source()
    |> normalize_markdown()
    |> normalize_items()
    |> normalize_options()
    |> normalize_option_groups()
    |> normalize_data()
    |> normalize_series()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Normalizes component input."
  @spec normalize(input()) :: t()
  def normalize(%__MODULE__{} = component), do: component
  def normalize(value) when is_binary(value), do: new(%{kind: :text, text: value})
  def normalize(value) when is_map(value), do: new(value)

  @doc "Serializes the component into a plain map with a type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = component) do
    component
    |> Map.from_struct()
    |> Map.update!(:items, &Enum.map(&1, fn item -> item |> normalize() |> to_map() end))
    |> Map.update!(:options, &Enum.map(&1, fn option -> option |> normalize() |> to_map() end))
    |> Map.update!(:option_groups, fn groups ->
      Enum.map(groups, fn group -> group |> normalize() |> to_map() end)
    end)
    |> Map.update!(:data, &Enum.map(&1, fn point -> point |> ChartData.new() |> ChartData.to_map() end))
    |> Map.update!(:series, fn series ->
      Enum.map(series, fn item -> item |> ChartSeries.new() |> ChartSeries.to_map() end)
    end)
    |> Map.update!(:markdown, fn
      nil -> nil
      %Markdown{} = markdown -> Markdown.to_map(markdown)
      other -> other
    end)
    |> Wire.to_plain()
    |> Map.put("__type__", "card_component")
  end

  @doc "Builds a component from serialized data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()

  defp normalize_markdown(attrs) do
    case attrs[:markdown] || attrs["markdown"] do
      nil ->
        attrs

      %Markdown{} = markdown ->
        Map.put(attrs, :markdown, markdown)

      %{} = markdown ->
        Map.put(attrs, :markdown, Markdown.new(markdown))

      value when is_binary(value) ->
        Map.put(attrs, :markdown, Markdown.parse(value))
    end
  end

  defp normalize_kind(attrs) do
    normalize_existing_atom_field(attrs, :kind, @kinds)
  end

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

  defp normalize_items(attrs) do
    items = attrs[:items] || attrs["items"] || []
    attrs |> Map.delete("items") |> Map.put(:items, Enum.map(items, &normalize/1))
  end

  defp normalize_options(attrs) do
    options = attrs[:options] || attrs["options"] || []
    attrs |> Map.delete("options") |> Map.put(:options, Enum.map(options, &normalize/1))
  end

  defp normalize_option_groups(attrs) do
    groups = attrs[:option_groups] || attrs["option_groups"] || []

    attrs
    |> Map.delete("option_groups")
    |> Map.put(:option_groups, Enum.map(groups, &normalize/1))
  end

  defp normalize_data(attrs) do
    data = attrs[:data] || attrs["data"] || []
    attrs |> Map.delete("data") |> Map.put(:data, Enum.map(data, &ChartData.new/1))
  end

  defp normalize_series(attrs) do
    series = attrs[:series] || attrs["series"] || []
    attrs |> Map.delete("series") |> Map.put(:series, Enum.map(series, &ChartSeries.new/1))
  end

  @doc false
  def validate(_schema, %__MODULE__{} = component) do
    cond do
      component.page_size != nil and component.page_size < 1 ->
        {:error, "page_size must be greater than zero"}

      component.min_query_length != nil and component.min_query_length < 0 ->
        {:error, "min_query_length must be zero or greater"}

      component.timeout_ms != nil and component.timeout_ms < 1 ->
        {:error, "timeout_ms must be greater than zero"}

      component.kind in [:pie_chart, :bar_chart, :area_chart, :line_chart] and
        component.data == [] and (component.categories == [] or component.series == []) ->
        {:error, "chart data or categories with named series must not be empty"}

      component.data != [] and (component.categories != [] or component.series != []) ->
        {:error, "chart data and named series are mutually exclusive"}

      component.series != [] and not valid_series_shape?(component) ->
        {:error, "each named series must have one value for each category and a unique name"}

      component.kind == :table and not valid_table_shape?(component) ->
        {:error, "table columns must not be empty and every row must match the column count"}

      component.kind == :external_select and blank?(component.id) ->
        {:error, "external select id must not be empty"}

      component.kind == :option_group and blank?(component.label || component.title) ->
        {:error, "option group label must not be empty"}

      true ->
        :ok
    end
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false

  defp valid_series_shape?(component) do
    names = Enum.map(component.series, & &1.name)

    component.categories != [] and Enum.all?(component.categories, &valid_category?/1) and
      Enum.uniq(names) == names and
      Enum.all?(component.series, &(length(&1.values) == length(component.categories)))
  end

  defp valid_category?(category) when is_binary(category), do: String.trim(category) != ""
  defp valid_category?(_category), do: false

  defp valid_table_shape?(component) do
    column_count = length(component.columns)

    component.columns != [] and Enum.all?(component.columns, &is_binary/1) and
      Enum.all?(component.rows, fn row ->
        is_list(row) and length(row) == column_count
      end)
  end
end
