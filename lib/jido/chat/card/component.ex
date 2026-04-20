defmodule Jido.Chat.Card.Component do
  @moduledoc """
  Canonical card component used by `Jido.Chat.Card`.
  """

  alias Jido.Chat.Markdown
  alias Jido.Chat.Wire

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
    :table,
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
              style: Zoi.string() |> Zoi.nullish(),
              disabled: Zoi.boolean() |> Zoi.default(false),
              markdown: Zoi.any() |> Zoi.nullish(),
              items: Zoi.list() |> Zoi.default([]),
              options: Zoi.list() |> Zoi.default([]),
              columns: Zoi.list() |> Zoi.default([]),
              rows: Zoi.list() |> Zoi.default([]),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

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
    |> normalize_markdown()
    |> normalize_items()
    |> normalize_options()
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

  defp normalize_items(attrs) do
    items = attrs[:items] || attrs["items"] || []
    attrs |> Map.delete("items") |> Map.put(:items, Enum.map(items, &normalize/1))
  end

  defp normalize_options(attrs) do
    options = attrs[:options] || attrs["options"] || []
    attrs |> Map.delete("options") |> Map.put(:options, Enum.map(options, &normalize/1))
  end
end
