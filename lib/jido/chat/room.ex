defmodule Jido.Chat.Room do
  @moduledoc """
  Represents a conversation room/chat.

  Rooms are the primary conversation container and can be bound to
  external channels (Telegram chats, Discord channels, etc.).
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              type: Zoi.enum([:direct, :group, :channel, :thread]),
              name: Zoi.string() |> Zoi.nullish(),
              external_bindings: Zoi.map() |> Zoi.default(%{}),
              metadata: Zoi.map() |> Zoi.default(%{}),
              inserted_at: Zoi.struct(DateTime) |> Zoi.nullish()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Room"
  def schema, do: @schema

  @doc "Creates a new room with generated ID and timestamp"
  def new(attrs) when is_map(attrs) do
    attrs
    |> Jido.Chat.Schema.put_default(:id, Jido.Chat.ID.generate!())
    |> Jido.Chat.Schema.put_default(:inserted_at, DateTime.utc_now())
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end
end
