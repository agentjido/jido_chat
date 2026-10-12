defmodule Jido.Chat.Thread do
  @moduledoc """
  Retained thread identity and metadata record.

  Provider communication uses a configured binding and typed request Signals.
  This record does not select a transport or return a communication envelope.
  """
  alias Jido.Chat.Wire

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              adapter_name: Zoi.atom(),
              adapter: Zoi.any(),
              external_room_id: Zoi.any(),
              external_thread_id: Zoi.string() |> Zoi.nullish(),
              channel_id: Zoi.string() |> Zoi.nullish(),
              is_dm: Zoi.boolean() |> Zoi.default(false),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the schema for a thread record."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates a thread record."
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    attrs
    |> Map.put_new(:id, Jido.Chat.ID.generate!())
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Returns the retained primary channel key."
  @spec channel_id(t()) :: String.t() | nil
  def channel_id(thread), do: thread.channel_id || to_string(thread.external_room_id)

  @doc "Serializes a domain record without executing provider work."
  @spec to_map(t()) :: map()
  def to_map(thread) do
    thread
    |> Map.from_struct()
    |> Map.update!(:adapter, &Wire.encode_module/1)
    |> Wire.to_plain()
    |> Map.put("__type__", "thread")
  end

  @doc "Builds a domain record from its stored form."
  @spec from_map(map()) :: t()
  def from_map(map) do
    adapter = map[:adapter] || map["adapter"]

    map
    |> Map.drop(["__type__", :__type__, "adapter", :adapter])
    |> Map.put(:adapter, Wire.decode_module(adapter))
    |> new()
  end
end
