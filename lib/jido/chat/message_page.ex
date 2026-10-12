defmodule Jido.Chat.MessagePage do
  @moduledoc """
  Canonical page of normalized messages for thread/channel history.
  """

  alias Jido.Chat.Message

  @schema Zoi.struct(
            __MODULE__,
            %{
              messages: Zoi.array(Zoi.struct(Message)) |> Zoi.default([]),
              next_cursor: Zoi.string() |> Zoi.nullish(),
              direction: Zoi.enum([:forward, :backward]) |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for MessagePage."
  def schema, do: @schema

  @doc "Creates a canonical message page and normalizes message entries."
  def new(attrs) when is_map(attrs) do
    attrs
    |> normalize_messages()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  defp normalize_messages(attrs) do
    messages = attrs[:messages] || attrs["messages"] || []

    normalized =
      Enum.map(messages, fn
        %Message{} = message ->
          message

        map when is_map(map) ->
          Message.new(map)

        other ->
          other
      end)

    Map.put(attrs, :messages, normalized)
  end
end
