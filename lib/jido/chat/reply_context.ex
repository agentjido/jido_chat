defmodule Jido.Chat.ReplyContext do
  @moduledoc """
  Shallow quoted-message context preserved with a message reply.

  This is intentionally not a nested message. It contains only the quoted
  message ID, provider ID, text, and author fields that providers can supply
  without lookup.
  """

  alias Jido.Chat.Author

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string() |> Zoi.nullish(),
              external_message_id: Zoi.any() |> Zoi.nullish(),
              text: Zoi.string() |> Zoi.nullish(),
              author: Zoi.struct(Author) |> Zoi.nullish()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for ReplyContext."
  def schema, do: @schema

  @doc "Creates a shallow reply context from map input."
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    attrs
    |> normalize_author()
    |> select_fields()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Serializes the reply context with a revivable type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = context) do
    context
    |> Map.from_struct()
    |> Jido.Chat.Wire.to_plain()
    |> Map.put("__type__", "reply_context")
  end

  @doc "Builds a reply context from serialized map data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()

  defp normalize_author(%{author: %Author{}} = attrs), do: attrs

  defp normalize_author(%{author: author} = attrs) when is_map(author),
    do: Map.put(attrs, :author, Author.new(author))

  defp normalize_author(%{"author" => %Author{}} = attrs), do: attrs

  defp normalize_author(%{"author" => author} = attrs) when is_map(author),
    do: attrs |> Map.delete("author") |> Map.put(:author, Author.new(author))

  defp normalize_author(attrs), do: attrs

  defp select_fields(attrs) do
    %{
      id: attrs[:id] || attrs["id"],
      external_message_id: attrs[:external_message_id] || attrs["external_message_id"],
      text: attrs[:text] || attrs["text"],
      author: attrs[:author] || attrs["author"]
    }
  end
end
