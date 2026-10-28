defmodule Jido.Chat.Actor do
  @moduledoc "Portable identity for a chat message author."

  @kinds [:human, :agent, :bot, :system, :unknown]
  @fields [:id, :kind, :username, :display_name, :avatar_url, :is_self, :metadata]
  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string() |> Zoi.min(1),
              kind: Zoi.enum(@kinds) |> Zoi.default(:unknown),
              username: Zoi.string() |> Zoi.nullish(),
              display_name: Zoi.string() |> Zoi.nullish(),
              avatar_url: Zoi.string() |> Zoi.nullish(),
              is_self: Zoi.boolean() |> Zoi.default(false),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the portable actor schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates a portable actor."
  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = value), do: value |> Map.from_struct() |> new()

  def new(attrs) when is_map(attrs) do
    attrs
    |> Jido.Chat.Value.without_marker()
    |> Jido.Chat.Value.normalize_keys(@fields)
    |> Jido.Chat.Value.normalize_enum(:kind, @kinds)
    |> infer_bot_kind()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Serializes the actor to a portable map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value), do: Jido.Chat.Value.plain_struct(new(value), "actor")

  @doc "Restores an actor from a portable map."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: new(map)

  defp infer_bot_kind(%{kind: :unknown, is_bot: true} = attrs),
    do: attrs |> Map.put(:kind, :bot) |> Map.delete(:is_bot)

  defp infer_bot_kind(%{is_bot: true} = attrs),
    do: attrs |> Map.put_new(:kind, :bot) |> Map.delete(:is_bot)

  defp infer_bot_kind(%{"is_bot" => true} = attrs),
    do: attrs |> Map.put_new(:kind, :bot) |> Map.delete("is_bot")

  defp infer_bot_kind(attrs), do: Map.drop(attrs, [:is_bot, "is_bot"])
end
