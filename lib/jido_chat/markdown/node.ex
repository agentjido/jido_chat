defmodule Jido.Chat.Markdown.Node do
  @moduledoc """
  Canonical Markdown AST node used by `Jido.Chat.Markdown`.
  """

  alias Jido.Chat.Wire

  @node_types [
    :root,
    :paragraph,
    :text,
    :strong,
    :emphasis,
    :link,
    :code,
    :code_block,
    :heading,
    :list,
    :list_item,
    :blockquote,
    :table,
    :table_row,
    :table_cell,
    :divider
  ]

  @schema Zoi.struct(
            __MODULE__,
            %{
              type: Zoi.enum(@node_types),
              text: Zoi.string() |> Zoi.nullish(),
              url: Zoi.string() |> Zoi.nullish(),
              language: Zoi.string() |> Zoi.nullish(),
              level: Zoi.integer() |> Zoi.nullish(),
              ordered: Zoi.boolean() |> Zoi.nullish(),
              start: Zoi.integer() |> Zoi.nullish(),
              align: Zoi.string() |> Zoi.nullish(),
              children: Zoi.list() |> Zoi.default([]),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type node_type ::
          :root
          | :paragraph
          | :text
          | :strong
          | :emphasis
          | :link
          | :code
          | :code_block
          | :heading
          | :list
          | :list_item
          | :blockquote
          | :table
          | :table_row
          | :table_cell
          | :divider

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the schema for a Markdown node."
  def schema, do: @schema

  @doc "Creates a canonical Markdown node."
  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = node), do: node

  def new(attrs) when is_map(attrs) do
    attrs
    |> normalize_children()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Serializes a Markdown node into a plain map with a type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = node) do
    node
    |> Map.from_struct()
    |> Map.update!(:children, &Enum.map(&1, fn child -> child |> normalize() |> to_map() end))
    |> Wire.to_plain()
    |> Map.put("__type__", "markdown_node")
  end

  @doc "Builds a Markdown node from serialized map data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()

  @doc "Normalizes a Markdown node input."
  @spec normalize(t() | map() | String.t() | nil) :: t() | nil
  def normalize(nil), do: nil
  def normalize(%__MODULE__{} = node), do: node
  def normalize(value) when is_binary(value), do: new(%{type: :text, text: value})
  def normalize(value) when is_map(value), do: new(value)

  defp normalize_children(attrs) do
    children =
      attrs[:children] || attrs["children"] || []

    attrs
    |> Map.delete("children")
    |> Map.put(:children, Enum.map(children, &normalize/1))
  end
end
