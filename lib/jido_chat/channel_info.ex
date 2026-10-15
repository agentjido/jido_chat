defmodule Jido.Chat.ChannelInfo do
  @moduledoc """
  Canonical channel metadata payload.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              name: Zoi.string() |> Zoi.nullish(),
              is_dm: Zoi.boolean() |> Zoi.nullish(),
              member_count: Zoi.integer() |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for ChannelInfo."
  def schema, do: @schema

  @doc "Creates canonical channel metadata."
  def new(attrs) when is_map(attrs), do: Jido.Chat.Schema.parse!(__MODULE__, @schema, attrs)
end
