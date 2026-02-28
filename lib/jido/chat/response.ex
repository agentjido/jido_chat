defmodule Jido.Chat.Response do
  @moduledoc """
  Canonical normalized outbound send/edit result.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              external_message_id: Zoi.string() |> Zoi.nullish(),
              external_room_id: Zoi.any() |> Zoi.nullish(),
              timestamp: Zoi.any() |> Zoi.nullish(),
              channel_type: Zoi.atom() |> Zoi.nullish(),
              status: Zoi.enum([:sent, :edited, :accepted, :failed]) |> Zoi.default(:sent),
              raw: Zoi.any() |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{}),
              message_id: Zoi.any() |> Zoi.nullish(),
              chat_id: Zoi.any() |> Zoi.nullish(),
              channel_id: Zoi.any() |> Zoi.nullish(),
              date: Zoi.any() |> Zoi.nullish()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Response."
  def schema, do: @schema

  @doc "Creates a canonical response struct from adapter data."
  def new(attrs) when is_map(attrs) do
    fetch = fn key ->
      Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
    end

    raw_timestamp = fetch.(:timestamp) || fetch.(:date)

    external_message_id =
      fetch.(:external_message_id) ||
        fetch.(:message_id)

    external_room_id =
      fetch.(:external_room_id) ||
        fetch.(:chat_id) ||
        fetch.(:channel_id)

    channel_type = fetch.(:channel_type)

    normalized_timestamp =
      case normalize_timestamp(raw_timestamp) do
        nil -> raw_timestamp
        dt -> dt
      end

    %{
      external_message_id: stringify(external_message_id),
      external_room_id: external_room_id,
      timestamp: normalized_timestamp,
      channel_type: channel_type,
      status: fetch.(:status) || :sent,
      raw: fetch.(:raw),
      metadata: fetch.(:metadata) || %{},
      message_id: external_message_id,
      chat_id: fetch.(:chat_id) || maybe_chat_id(channel_type, external_room_id),
      channel_id: fetch.(:channel_id) || maybe_channel_id(channel_type, external_room_id),
      date: fetch.(:date) || raw_timestamp
    }
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  defp maybe_chat_id(:telegram, external_room_id), do: external_room_id
  defp maybe_chat_id(_, _), do: nil

  defp maybe_channel_id(:discord, external_room_id), do: external_room_id
  defp maybe_channel_id(_, _), do: nil

  defp stringify(nil), do: nil
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: to_string(value)

  defp normalize_timestamp(nil), do: nil
  defp normalize_timestamp(%DateTime{} = dt), do: dt

  defp normalize_timestamp(value) when is_integer(value) do
    case DateTime.from_unix(value) do
      {:ok, dt} -> dt
      _ -> nil
    end
  end

  defp normalize_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp normalize_timestamp(_), do: nil
end
