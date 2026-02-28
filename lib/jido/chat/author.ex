defmodule Jido.Chat.Author do
  @moduledoc """
  Canonical author identity used by normalized incoming messages.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              user_id: Zoi.string(),
              user_name: Zoi.string(),
              full_name: Zoi.string() |> Zoi.nullish(),
              is_bot: Zoi.boolean() |> Zoi.default(false),
              is_me: Zoi.boolean() |> Zoi.default(false),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Author."
  def schema, do: @schema

  @doc "Creates a new author."
  def new(attrs) when is_map(attrs), do: Jido.Chat.Schema.parse!(__MODULE__, @schema, attrs)
end
