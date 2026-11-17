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

  @schema Jido.Joi.struct(
            __MODULE__,
            %{
              type: Jido.Joi.enum(Enum.map(@node_types, &{&1, Atom.to_string(&1)}), coerce: true),
              text: Jido.Joi.string() |> Jido.Joi.nullable() |> Jido.Joi.optional(),
              url: Jido.Joi.string() |> Jido.Joi.nullable() |> Jido.Joi.optional(),
              language: Jido.Joi.string() |> Jido.Joi.nullable() |> Jido.Joi.optional(),
              level:
                Jido.Joi.integer() |> Jido.Joi.min(1) |> Jido.Joi.max(6) |> Jido.Joi.nullable() |> Jido.Joi.optional(),
              ordered: Jido.Joi.boolean() |> Jido.Joi.nullable() |> Jido.Joi.optional(),
              start: Jido.Joi.integer() |> Jido.Joi.nullable() |> Jido.Joi.optional(),
              align: Jido.Joi.string() |> Jido.Joi.nullable() |> Jido.Joi.optional(),
              children: Jido.Joi.list(Jido.Joi.struct(__MODULE__)) |> Jido.Joi.default([]),
              metadata: Jido.Joi.map() |> Jido.Joi.default(%{})
            },
            coerce: true
          )
          |> Jido.Joi.refine({Jido.Chat.Wire, :portable, []})

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

  @type t :: unquote(Jido.Joi.type_spec(@schema))

  @enforce_keys Jido.Joi.enforce_keys(@schema)
  defstruct Jido.Joi.struct_fields(@schema)

  @doc "Returns the schema for a Markdown node."
  def schema, do: @schema

  @doc "Creates a canonical Markdown node."
  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = node), do: node |> Map.from_struct() |> new()

  def new(attrs) when is_map(attrs) do
    attrs
    |> Jido.Chat.Value.without_marker()
    |> normalize_children()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Serializes a Markdown node into a plain map with a type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = node) do
    node |> new() |> encode()
  end

  defp encode(node) do
    node
    |> Map.from_struct()
    |> Map.delete(:children)
    |> Wire.to_plain()
    |> Map.put("children", Enum.map(node.children, &encode/1))
    |> Map.put("__type__", "markdown_node")
  end

  @doc "Builds a Markdown node from serialized map data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Jido.Chat.Value.without_marker() |> new()

  @doc "Normalizes a Markdown node input."
  @spec normalize(t() | map() | String.t() | nil) :: t() | nil
  def normalize(nil), do: nil
  def normalize(%__MODULE__{} = node), do: new(node)
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
