defmodule Jido.Chat.MessageDeletedEvent do
  @moduledoc """
  A normalized event for deletion of an existing message.

  `message_id` always identifies the deleted provider message. If the provider
  does not supply deleted content, `message` is `nil`. Core does not fetch or
  recover the missing content.
  """

  alias Jido.Chat.{Author, ChannelRef, Message, MessageLifecycleEvent, Thread}

  @schema Zoi.struct(
            __MODULE__,
            %{
              adapter: Zoi.any() |> Zoi.nullish(),
              adapter_name: Zoi.atom() |> Zoi.nullish(),
              thread_id: Zoi.string() |> Zoi.nullish(),
              channel_id: Zoi.string() |> Zoi.nullish(),
              message_id: Zoi.string(),
              author: Zoi.struct(Author) |> Zoi.nullish(),
              timestamp: Zoi.any() |> Zoi.nullish(),
              thread: Zoi.struct(Thread) |> Zoi.nullish(),
              channel: Zoi.struct(ChannelRef) |> Zoi.nullish(),
              message: Zoi.struct(Message) |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{}),
              raw: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for MessageDeletedEvent."
  def schema, do: @schema

  @doc "Creates a normalized message-deleted event."
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    attrs
    |> MessageLifecycleEvent.normalize()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Serializes the event into a plain map with a type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = event),
    do: MessageLifecycleEvent.to_map(event, "message_deleted_event")

  @doc "Builds the event from serialized map data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()
end
