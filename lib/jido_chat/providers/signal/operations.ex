defmodule Jido.Chat.Signal.Operations do
  @moduledoc false

  alias Jido.Chat.{Client, Signal}
  alias Jido.Chat.Signal.{Adapter, AttachmentRef}

  @doc false
  def invoke(operation, %Client{adapter: Adapter} = client, request, opts) do
    call(
      operation,
      client,
      request.data,
      client.credentials[:account],
      Keyword.merge(client.config, opts)
    )
  end

  def invoke(_, _, _, _), do: {:error, {:not_attempted, :unsupported}}

  defp call(:send_message, client, data, account, opts) do
    send_message(client, data["room_id"], data["text"], data, account, opts)
  end

  defp call(:send_file, client, data, account, opts) do
    with {:ok, attachment} <- attachment(data["source"]),
         send_opts <- Keyword.put(opts, :attachments, [attachment]) do
      send_message(client, data["room_id"], data["caption"] || "", data, account, send_opts)
    end
  end

  defp call(_, _, _, _, _), do: {:error, {:not_attempted, :unsupported}}

  defp send_message(client, room_id, text, data, account, opts) do
    opts =
      opts
      |> optional(:reply_to_id, data["reply_to_id"])
      |> optional(:thread_id, data["thread_id"])

    with {:ok, raw} <- client.transport.send_message(account, room_id, text, opts) do
      result =
        %{
          "id" => identifier(field(raw, "timestamp") || field(raw, "id")),
          "room_id" => room_id,
          "text" => text,
          "status" => "sent"
        }
        |> optional("reply_to_id", data["reply_to_id"])
        |> optional("thread_id", data["thread_id"])

      case Zoi.parse(Signal.Schemas.result(:message), result) do
        {:ok, checked} -> {:ok, checked}
        _ -> {:error, :invalid_provider_result}
      end
    end
  end

  defp attachment(%{"content_base64" => content, "filename" => filename}) do
    value = %{data: content, filename: filename}

    case AttachmentRef.ref(value) do
      {:ok, _} -> {:ok, value}
      {:error, _} -> {:error, :invalid_file_source}
    end
  end

  defp attachment(%{"kind" => kind, "id" => id}) when kind in ["file", "media"] do
    case AttachmentRef.ref(id) do
      {:ok, _} -> {:ok, id}
      {:error, _} -> {:error, :invalid_file_source}
    end
  end

  defp attachment(_), do: {:error, :invalid_file_source}

  defp identifier(nil), do: nil
  defp identifier(value), do: to_string(value)
  defp optional(value, _key, nil), do: value
  defp optional(value, key, item), do: put(value, key, item)
  defp put(value, key, item) when is_map(value), do: Map.put(value, key, item)
  defp put(value, key, item) when is_list(value), do: Keyword.put(value, key, item)

  defp field(map, key) when is_map(map) do
    Map.get(map, key) ||
      Enum.find_value(map, fn
        {atom, value} when is_atom(atom) -> if Atom.to_string(atom) == key, do: value
        _ -> nil
      end)
  end

  defp field(_, _), do: nil
end
