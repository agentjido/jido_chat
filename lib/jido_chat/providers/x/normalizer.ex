defmodule Jido.Chat.X.Normalizer do
  @moduledoc false

  alias Jido.Chat.{Client, Delivery}
  alias Jido.Chat.Signal.{Identity, MessageReceived, NormalizationFailed, Policy}

  @doc false
  def normalize(%Client{} = client, input) when is_map(input) or is_list(input) do
    events = inputs(input)
    delivery_id = "x:" <> digest({client.id, Enum.map(events, &event_key/1)})

    with {:ok, signals} <- map_events(client, delivery_id, events),
         do: Delivery.new(client, delivery_id, signals)
  rescue
    _ -> Policy.error(:invalid_delivery)
  catch
    _, _ -> Policy.error(:invalid_delivery)
  end

  def normalize(_, _), do: Policy.error(:invalid_delivery)

  defp inputs(items) when is_list(items), do: Enum.flat_map(items, &inputs/1)

  defp inputs(payload) do
    cond do
      is_list(field(payload, "direct_message_events")) -> field(payload, "direct_message_events")
      is_list(field(payload, "dm_events")) -> field(payload, "dm_events")
      is_list(field(payload, "data")) -> field(payload, "data")
      is_map(field(payload, "dm_event")) -> [field(payload, "dm_event")]
      true -> [payload]
    end
  end

  defp map_events(client, delivery_id, events) do
    result =
      events
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {event, index}, {:ok, acc} ->
        case map_event(client, delivery_id, event, index) do
          {:ok, signal} -> {:cont, {:ok, [signal | acc]}}
          error -> {:halt, error}
        end
      end)

    case result do
      {:ok, signals} -> {:ok, Enum.reverse(signals)}
      error -> error
    end
  end

  defp map_event(client, delivery_id, event, index) when is_map(event) do
    details = event_details(event)

    if message_event?(details) do
      message_signal(client, delivery_id, event, details)
    else
      failure(client, delivery_id, event, index, details.kind, details.room_id)
    end
  end

  defp map_event(client, delivery_id, event, index),
    do: failure(client, delivery_id, event, index, "invalid", nil)

  defp event_details(event) do
    message_data = get_in(event, ["message_create", "message_data"]) || %{}
    sender_id = field(event, "sender_id") || get_in(event, ["message_create", "sender_id"])
    conversation_id = field(event, "dm_conversation_id") || field(event, "conversation_id")

    %{
      kind: field(event, "type") || field(event, "event_type") || "message_create",
      message_data: message_data,
      sender_id: sender_id,
      message_id: field(event, "id") || field(event, "dm_event_id"),
      conversation_id: conversation_id,
      room_id: room_id(conversation_id, sender_id)
    }
  end

  defp room_id(conversation_id, _sender_id) when not is_nil(conversation_id),
    do: "conversation:" <> to_string(conversation_id)

  defp room_id(_conversation_id, sender_id), do: identifier(sender_id)

  defp message_event?(details) do
    details.kind in ["MessageCreate", "message_create"] and present?(details.room_id) and
      present?(details.message_id) and present?(details.sender_id)
  end

  defp message_signal(client, delivery_id, event, details) do
    data =
      %{
        "item_id" => "x:item:" <> event_key(event),
        "delivery_id" => delivery_id,
        "room_id" => details.room_id,
        "message_id" => identifier(details.message_id),
        "sender" => %{"id" => identifier(details.sender_id)},
        "text" => field(event, "text") || field(details.message_data, "text") || "",
        "conversation_kind" => "direct"
      }
      |> optional("thread_id", identifier(details.conversation_id))
      |> optional(
        "timestamp",
        timestamp(field(event, "created_at") || field(event, "created_timestamp"))
      )

    signal(client, MessageReceived, details.room_id, data)
  end

  defp failure(client, delivery_id, event, index, kind, room_id) do
    data =
      %{
        "item_id" => "x:item:" <> event_key(event),
        "delivery_id" => delivery_id,
        "code" =>
          if(kind in ["invalid", "message_create", "MessageCreate"],
            do: "invalid_item",
            else: "unsupported_item"
          ),
        "item_index" => index,
        "provider_kind" => to_string(kind)
      }
      |> optional("room_id", room_id)

    signal(client, NormalizationFailed, room_id, data)
  end

  defp signal(client, definition, room_id, data) do
    subject = if present?(room_id), do: Identity.conversation_subject(client.id, room_id)
    definition.new(data, source: client.source, subject: subject)
  end

  defp event_key(event) when is_map(event),
    do: identifier(field(event, "id") || field(event, "dm_event_id")) || digest(event)

  defp event_key(event), do: digest(event)

  defp digest(value),
    do:
      :crypto.hash(:sha256, :erlang.term_to_binary(canonical(value), [:deterministic]))
      |> Base.url_encode64(padding: false)

  defp canonical(%_{} = value), do: value |> Map.from_struct() |> canonical()

  defp canonical(value) when is_map(value),
    do: value |> Enum.map(fn {k, v} -> {to_string(k), canonical(v)} end) |> Enum.sort()

  defp canonical(value) when is_list(value), do: Enum.map(value, &canonical/1)
  defp canonical(value), do: value
  defp identifier(nil), do: nil
  defp identifier(value), do: to_string(value)
  defp present?(value), do: is_binary(value) and value != ""
  defp timestamp(nil), do: nil
  defp timestamp(value), do: to_string(value)
  defp optional(map, _, nil), do: map
  defp optional(map, key, value), do: Map.put(map, key, value)

  defp field(map, key) when is_map(map) do
    Map.get(map, key) ||
      Enum.find_value(map, fn
        {atom, value} when is_atom(atom) -> if Atom.to_string(atom) == key, do: value
        _ -> nil
      end)
  end

  defp field(_, _), do: nil
end
