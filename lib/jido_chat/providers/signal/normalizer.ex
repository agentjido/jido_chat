defmodule Jido.Chat.Signal.Normalizer do
  @moduledoc false

  alias Jido.Chat.{Client, Delivery}
  alias Jido.Chat.Signal.{Identity, MessageReceived, NormalizationFailed, Policy}

  @limits [:signal_too_large, :delivery_too_large, :too_many_signals, :too_many_failures]

  @doc false
  @spec normalize(Client.t(), term()) ::
          {:ok, Delivery.t()} | {:error, Jido.Chat.Errors.Contract.t()}
  def normalize(%Client{} = client, input)
      when is_map(input) or is_list(input) or is_nil(input) do
    items = if is_list(input), do: input, else: [input]
    delivery_id = "signal:" <> digest({client.id, Enum.map(items, &provider_identity/1)})

    with {:ok, signals} <- facts(client, delivery_id, items),
         do: Delivery.new(client, delivery_id, signals)
  rescue
    _ -> Policy.error(:invalid_delivery)
  catch
    _, _ -> Policy.error(:invalid_delivery)
  end

  def normalize(_, _), do: Policy.error(:invalid_delivery)

  defp facts(client, delivery_id, items) do
    result =
      items
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, &append_fact(&1, &2, client, delivery_id))

    case result do
      {:ok, signals} -> {:ok, Enum.reverse(signals)}
      error -> error
    end
  end

  defp append_fact({item, index}, {:ok, acc}, client, delivery_id) do
    case fact(client, delivery_id, item) do
      {:ok, signal} ->
        {:cont, {:ok, [signal | acc]}}

      {:error, %Jido.Chat.Errors.Contract{code: code}} = error when code in @limits ->
        {:halt, error}

      _other ->
        append_failure(client, delivery_id, item, index, acc)
    end
  end

  defp append_failure(client, delivery_id, item, index, acc) do
    case failure(client, delivery_id, item, index) do
      {:ok, signal} -> {:cont, {:ok, [signal | acc]}}
      error -> {:halt, error}
    end
  end

  defp fact(client, delivery_id, item) do
    with {:ok, envelope} <- envelope(item),
         {:ok, data} <- data_message(envelope),
         {:ok, source, room, group, stamp} <- message_identity(envelope, data),
         {:ok, text, attachments} <- message_content(data) do
      sender =
        %{"id" => source}
        |> optional("display_name", non_blank(envelope, ["sourceName"]))
        |> optional("is_self", if(sent_message?(envelope), do: true))

      fields =
        %{
          "item_id" => item_identity(item),
          "delivery_id" => delivery_id,
          "room_id" => room,
          "message_id" => to_string(stamp),
          "sender" => sender,
          "text" => text,
          "conversation_kind" => if(group, do: "group", else: "direct")
        }
        |> optional("media", media(client, attachments))
        |> optional("thread_id", group)
        |> optional("reply_to_id", quote_id(data["quote"]))
        |> optional("timestamp", timestamp(stamp))

      signal(client, MessageReceived, room, fields)
    else
      result -> result
    end
  end

  defp failure(client, delivery_id, item, index) do
    data = %{
      "item_id" => item_identity(item),
      "delivery_id" => delivery_id,
      "code" => if(provider_kind(item) == "message", do: "invalid_item", else: "unsupported_item"),
      "item_index" => index,
      "provider_kind" => provider_kind(item)
    }

    signal(client, NormalizationFailed, nil, data)
  end

  defp signal(client, definition, room, data) do
    subject = if is_binary(room), do: Identity.conversation_subject(client.id, room)
    definition.new(data, source: client.source, subject: subject)
  end

  defp envelope(%{"envelope" => envelope}) when is_map(envelope), do: {:ok, envelope}

  defp envelope(%{"params" => %{"envelope" => envelope}}) when is_map(envelope),
    do: {:ok, envelope}

  defp envelope(%{"params" => %{"result" => %{"envelope" => envelope}}})
       when is_map(envelope),
       do: {:ok, envelope}

  defp envelope(_), do: :invalid

  defp data_message(envelope) do
    data = envelope["dataMessage"] || nested(envelope["syncMessage"], "sentMessage")
    if is_map(data), do: {:ok, data}, else: :invalid
  end

  defp message_identity(envelope, data) do
    source = envelope["sourceUuid"] || envelope["sourceNumber"] || envelope["source"]
    group = nested(data["groupInfo"], "groupId")
    room = conversation(envelope, data, group, source)
    stamp = data["timestamp"] || envelope["timestamp"]

    if present?(source) and present?(room) and valid_stamp?(stamp),
      do: {:ok, source, room, group, stamp},
      else: :invalid
  end

  defp message_content(data) do
    text = data["message"] || ""
    attachments = data["attachments"] || []

    if is_binary(text) and is_list(attachments) and (String.trim(text) != "" or attachments != []),
      do: {:ok, text, attachments},
      else: :invalid
  end

  defp conversation(_, _, group, _) when is_binary(group) and group != "", do: "group:" <> group
  defp conversation(_envelope, %{"groupV2" => _}, _group, _source), do: nil

  defp conversation(envelope, data, _group, source) do
    if sent_message?(envelope) do
      data["destinationUuid"] || data["destinationNumber"] || data["destination"]
    else
      source
    end
  end

  defp media(_client, []), do: nil

  defp media(client, attachments) do
    Enum.map(attachments, fn attachment ->
      name = non_blank(attachment, ["filename", "fileName"])
      media_type = normalize_media_type(non_blank(attachment, ["contentType", "content_type"]))

      %{
        "kind" => media_kind(media_type, name),
        "resource_ref" => %{
          "client_id" => client.id,
          "kind" => "media",
          "id" => "signal:attachment:" <> digest(attachment)
        }
      }
      |> optional("name", name)
      |> optional("media_type", media_type)
    end)
  end

  defp normalize_media_type(value) when is_binary(value) do
    value = value |> String.split(";", parts: 2) |> hd() |> String.trim() |> String.downcase()
    if Regex.match?(~r|^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$|, value), do: value
  end

  defp normalize_media_type(_), do: nil
  defp media_kind("image/" <> _, _), do: "image"
  defp media_kind("audio/" <> _, _), do: "audio"
  defp media_kind("video/" <> _, _), do: "video"

  defp media_kind(_, name) when is_binary(name) do
    if String.downcase(Path.extname(name)) in [".png", ".jpg", ".jpeg", ".gif", ".webp"],
      do: "image",
      else: "file"
  end

  defp media_kind(_, _), do: "file"

  defp provider_identity(item) do
    with {:ok, envelope} <- envelope(item),
         {:ok, data} <- data_message(envelope),
         {:ok, source, room, _group, stamp} <- message_identity(envelope, data) do
      {source, room, stamp}
    else
      _ -> digest(item)
    end
  end

  defp provider_kind(item) do
    with {:ok, envelope} <- envelope(item),
         {:ok, _data} <- data_message(envelope) do
      "message"
    else
      _ -> "unknown"
    end
  end

  defp item_identity(item), do: "signal:item:" <> digest({provider_identity(item), :message, 0})
  defp sent_message?(envelope), do: is_map(nested(envelope["syncMessage"], "sentMessage"))
  defp nested(map, key) when is_map(map), do: map[key]
  defp nested(_, _), do: nil
  defp present?(value), do: is_binary(value) and value != ""
  defp valid_stamp?(value), do: is_integer(value) or present?(value)

  defp quote_id(value) when is_map(value),
    do: identifier(value["id"] || value["timestamp"] || value["quoteTimestamp"])

  defp quote_id(_), do: nil

  defp timestamp(value) when is_integer(value) do
    case DateTime.from_unix(value, :millisecond) do
      {:ok, date} -> DateTime.to_iso8601(date)
      _ -> nil
    end
  end

  defp timestamp(_), do: nil
  defp identifier(nil), do: nil
  defp identifier(value), do: to_string(value)
  defp non_blank(map, keys), do: Enum.find_value(keys, &non_blank_value(map[&1]))
  defp non_blank_value(value) when is_binary(value), do: if(String.trim(value) != "", do: value)
  defp non_blank_value(_), do: nil
  defp optional(map, _key, nil), do: map
  defp optional(map, key, value), do: Map.put(map, key, value)

  defp digest(value) do
    :crypto.hash(:sha256, :erlang.term_to_binary(canonical(value), [:deterministic]))
    |> Base.url_encode64(padding: false)
  end

  defp canonical(%_{} = value), do: value |> Map.from_struct() |> canonical()

  defp canonical(value) when is_map(value),
    do: value |> Enum.map(fn {key, item} -> {to_string(key), canonical(item)} end) |> Enum.sort()

  defp canonical(value) when is_list(value), do: Enum.map(value, &canonical/1)
  defp canonical(value), do: value
end
