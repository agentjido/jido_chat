defmodule Jido.Chat.ThreadSummary do
  @moduledoc """
  Lightweight thread descriptor for channel-level thread listing.
  """

  alias Jido.Chat.Message

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

      nil ->
        attrs

      map when is_map(map) ->
        Map.put(attrs, :root_message, Message.new(map))

      _other ->
        attrs
    end
  end
end
