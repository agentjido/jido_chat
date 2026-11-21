defmodule Jido.Chat.X.Operations do
  @moduledoc false

  alias Jido.Chat.{Client, Signal}
  alias Jido.Chat.X.Adapter

  @doc false
  def invoke(operation, %Client{adapter: Adapter} = client, signal, opts) do
    call(operation, client, signal.data, Keyword.merge(client.config, opts))
  end

  def invoke(_, _, _, _), do: {:error, {:not_attempted, :unsupported}}

  defp call(:send_message, client, data, opts) do
    with {:ok, raw} <- send_text(client, data["room_id"], data["text"], opts) do
      message(raw, data["room_id"], "sent")
    end
  end

  defp call(:delete_message, client, data, opts) do
    with :ok <- client.transport.delete_dm_event(data["message_id"], opts) do
      {:ok, %{"acknowledged" => true}}
    end
  end

  defp call(:fetch_message, client, data, opts) do
    with {:ok, raw} <- client.transport.fetch_dm_event(data["message_id"], opts) do
      raw |> field("data") |> then(&message(&1 || raw, data["room_id"], "received"))
    end
  end

  defp call(:fetch_messages, client, data, opts) do
    room_id = data["room_id"]
    conversation_id = String.replace_prefix(room_id, "conversation:", "")
    query = Keyword.merge(opts, limit: data["limit"], cursor: data["cursor"])

    with {:ok, raw} <- client.transport.fetch_conversation_messages(conversation_id, query),
         events when is_list(events) <- field(raw, "data") || raw,
         {:ok, messages} <- map_messages(events, room_id) do
      next_cursor = field(field(raw, "meta"), "next_token")

      {:ok, %{"messages" => messages, "next_cursor" => next_cursor, "complete" => is_nil(next_cursor)}}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_provider_result}
    end
  end

  defp call(:open_dm, _client, data, _opts),
    do: {:ok, %{"id" => data["user_id"], "kind" => "direct"}}

  defp call(_, _, _, _), do: {:error, {:not_attempted, :unsupported}}

  defp send_text(client, "conversation:" <> conversation_id, text, opts),
    do: client.transport.send_conversation_message(conversation_id, text, opts)

  defp send_text(client, participant_id, text, opts),
    do: client.transport.send_dm(participant_id, text, opts)

  defp map_messages(events, room_id) do
    result =
      Enum.reduce_while(events, {:ok, []}, fn event, {:ok, acc} ->
        case message(event, room_id, "received") do
          {:ok, value} -> {:cont, {:ok, [value | acc]}}
          error -> {:halt, error}
        end
      end)

    case result do
      {:ok, messages} -> {:ok, Enum.reverse(messages)}
      error -> error
    end
  end

  defp message(raw, requested_room, status) when is_map(raw) do
    raw = if is_map(field(raw, "data")), do: field(raw, "data"), else: raw
    id = identifier(field(raw, "dm_event_id") || field(raw, "id"))
    conversation = identifier(field(raw, "dm_conversation_id") || field(raw, "conversation_id"))
    room_id = requested_room

    result =
      %{"id" => id, "room_id" => room_id, "status" => status}
      |> optional(
        "text",
        field(raw, "text") || get_in(raw, ["message_create", "message_data", "text"])
      )
      |> optional(
        "sender",
        actor(field(raw, "sender_id") || get_in(raw, ["message_create", "sender_id"]))
      )
      |> optional("thread_id", conversation)
      |> optional(
        "timestamp",
        timestamp(field(raw, "created_at") || field(raw, "created_timestamp"))
      )

    case Zoi.parse(Signal.Schemas.result(:message), result) do
      {:ok, checked} -> {:ok, checked}
      _ -> {:error, :invalid_provider_result}
    end
  end

  defp message(_, _, _), do: {:error, :invalid_provider_result}

  defp actor(nil), do: nil
  defp actor(id), do: %{"id" => identifier(id)}
  defp timestamp(nil), do: nil
  defp timestamp(value) when is_binary(value), do: value
  defp timestamp(value), do: to_string(value)
  defp identifier(nil), do: nil
  defp identifier(value), do: to_string(value)
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
