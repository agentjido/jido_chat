defmodule Jido.Chat.MessageSubject do
  @moduledoc """
  Normalized subject for a resource-backed conversation.

  Examples include an issue, a pull request, or a discussion. The adapter
  supplies the provider resource type and identifier. Core does not infer a
  subject from a room identifier.
  """

  alias Jido.Chat.Wire

  @schema Zoi.struct(
            __MODULE__,
            %{
              type: Zoi.string(min_length: 1),
              id: Zoi.string(min_length: 1),
              title: Zoi.string() |> Zoi.nullish(),
              url: Zoi.string() |> Zoi.nullish(),
              status: Zoi.string() |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for MessageSubject."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates a normalized message subject from atom-keyed or string-keyed input."
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    attrs
    |> normalize_attrs()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Serializes a message subject into a plain map with a type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = subject) do
    subject
    |> Map.from_struct()
    |> Wire.to_plain()
    |> Map.put("__type__", "message_subject")
  end

  @doc "Builds a message subject from serialized map data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()

  defp normalize_attrs(attrs) do
    %{
      type: attrs |> value([:type, "type"]) |> normalize_text(),
      id: attrs |> value([:id, "id"]) |> stringify(),
      title: value(attrs, [:title, "title"]),
      url: value(attrs, [:url, "url"]),
      status: attrs |> value([:status, "status"]) |> normalize_text(),
      metadata: value(attrs, [:metadata, "metadata"]) || %{}
    }
  end

  defp value(attrs, keys), do: Enum.find_value(keys, &Map.get(attrs, &1))

  defp normalize_text(nil), do: nil
  defp normalize_text(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_text(value) when is_binary(value), do: String.trim(value)
  defp normalize_text(value), do: value

  defp stringify(nil), do: nil
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: to_string(value)
end
