defmodule Jido.Chat.ThreadSummary do
  @moduledoc """
  Lightweight thread descriptor for channel-level thread listing.
  """

  alias Jido.Chat.{Incoming, Message}

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              last_reply_at: Zoi.any() |> Zoi.nullish(),
              reply_count: Zoi.integer() |> Zoi.nullish(),
              root_message: Zoi.struct(Message) |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for ThreadSummary."
  def schema, do: @schema

  @doc "Creates a thread summary and normalizes root message payload."
  def new(attrs) when is_map(attrs) do
    attrs
    |> normalize_root_message()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  defp normalize_root_message(attrs) do
    case attrs[:root_message] || attrs["root_message"] do
      %Message{} ->
        attrs

      %Incoming{} = incoming ->
        Map.put(attrs, :root_message, Message.from_incoming(incoming))

      nil ->
        attrs

      map when is_map(map) ->
        if Map.has_key?(map, :external_room_id) || Map.has_key?(map, "external_room_id") do
          message = map |> Incoming.new() |> Message.from_incoming()
          Map.put(attrs, :root_message, message)
        else
          Map.put(attrs, :root_message, Message.new(map))
        end

      _other ->
        attrs
    end
  end
end
