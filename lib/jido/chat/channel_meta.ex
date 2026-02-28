defmodule Jido.Chat.ChannelMeta do
  @moduledoc """
  Normalized channel-level metadata for `Jido.Chat.Incoming`.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              adapter_name: Zoi.atom() |> Zoi.nullish(),
              external_room_id: Zoi.any() |> Zoi.nullish(),
              external_thread_id: Zoi.string() |> Zoi.nullish(),
              chat_type: Zoi.atom() |> Zoi.nullish(),
              chat_title: Zoi.string() |> Zoi.nullish(),
              is_dm: Zoi.boolean() |> Zoi.default(false),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for ChannelMeta."
  def schema, do: @schema

  @doc "Creates a channel metadata struct from map input."
  def new(attrs) when is_map(attrs), do: Jido.Chat.Schema.parse!(__MODULE__, @schema, attrs)
end
