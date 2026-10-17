defmodule Jido.Chat.UserInfo do
  @moduledoc """
  Normalized provider user information.

  The `id` is the user identifier from one adapter. It is not a
  cross-platform identity. Adapters and runtimes can cache this data, but
  `jido_chat` does not provide a global user cache.
  """

  alias Jido.Chat.Wire

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(min_length: 1),
              username: Zoi.string() |> Zoi.nullish(),
              display_name: Zoi.string() |> Zoi.nullish(),
              email: Zoi.string() |> Zoi.nullish(),
              avatar_url: Zoi.string() |> Zoi.nullish(),
              is_bot: Zoi.boolean() |> Zoi.default(false),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for UserInfo."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates normalized user information from atom-keyed or string-keyed input."
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    attrs
    |> normalize_attrs()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Serializes user information into a plain map with a type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = user) do
    user
    |> Map.from_struct()
    |> Wire.to_plain()
    |> Map.put("__type__", "user_info")
  end

  @doc "Builds user information from serialized map data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()

  defp normalize_attrs(attrs) do
    %{
      id: attrs |> value([:id, "id", :user_id, "user_id"]) |> stringify(),
      username: value(attrs, [:username, "username", :user_name, "user_name"]),
      display_name: value(attrs, [:display_name, "display_name", :full_name, "full_name", :name, "name"]),
      email: value(attrs, [:email, "email"]),
      avatar_url: value(attrs, [:avatar_url, "avatar_url"]),
      is_bot: value(attrs, [:is_bot, "is_bot"]) || false,
      metadata: value(attrs, [:metadata, "metadata"]) || %{}
    }
  end

  defp value(attrs, keys), do: Enum.find_value(keys, &Map.get(attrs, &1))

  defp stringify(nil), do: nil
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: to_string(value)
end
