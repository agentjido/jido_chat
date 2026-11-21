defmodule Jido.Chat.Discord.Operations do
  @moduledoc false
  @compile {:no_warn_undefined, Req}

  alias Jido.Chat.Discord.{Adapter, Normalizer, Transport.REST}
  alias Jido.Chat.Providers.Dependencies
  import Normalizer, only: [field: 2, id: 2, compact: 1]

  @doc "Execute an admitted Chat operation with explicit private client options."
  def invoke(operation, %Jido.Chat.Client{adapter: Adapter, credentials: %{token: token}} = client, signal, opts)
      when is_binary(token) and token != "" do
    if signal.data["format"] == "html" do
      {:error, {:not_attempted, :unsupported_format}}
    else
      with :ok <- check_transport(client.transport) do
        call(operation, client, signal.data, Keyword.merge(client.config, opts))
      end
    end
  end

  def invoke(_, _, _, _), do: {:error, {:not_attempted, :missing_token}}

  defp check_transport(REST), do: Dependencies.req()
  defp check_transport(_custom), do: :ok

  defp call(:send_message, c, d, opts) do
    with {:ok, raw} <- api(c, :post, messages(d), text_payload(d), opts), do: message_result(c, raw, "sent", d)
  end

  defp call(:send_rich_message, c, d, opts) do
    payload = Map.merge(text_payload(d), Map.take(d, ["embeds", "components", "tts"]))
    with {:ok, raw} <- api(c, :post, messages(d), payload, opts), do: message_result(c, raw, "sent", d)
  end

  defp call(:start_message_thread, c, d, opts) do
    call(:create_thread, c, Map.put(d, "parent_message_id", d["message_id"]), opts)
  end

  defp call(:stream_text, c, d, opts) do
    # Consume the Enumerable only inside the Action task.
    text = Jido.Chat.Adapter.render_stream(Keyword.fetch!(opts, :stream))
    call(:send_message, c, Map.put(d, "text", text || ""), opts)
  end

  defp call(:edit_message, c, d, opts) do
    with {:ok, raw} <- api(c, :patch, message_path(d), text_payload(d), opts), do: message_result(c, raw, "updated", d)
  end

  defp call(:delete_message, c, d, opts), do: ack(c, :delete, message_path(d), nil, opts)
  defp call(:start_typing, c, d, opts), do: ack(c, :post, channel(d) <> "/typing", nil, opts)

  defp call(operation, c, d, opts) when operation in [:add_reaction, :remove_reaction] do
    method = if operation == :add_reaction, do: :put, else: :delete

    ack(
      c,
      method,
      message_path(d) <> "/reactions/" <> URI.encode(d["reaction"], &URI.char_unreserved?/1) <> "/@me",
      nil,
      opts
    )
  end

  defp call(:fetch_message, c, d, opts) do
    with {:ok, raw} <- api(c, :get, message_path(d), nil, opts), do: message_result(c, raw, "received", d)
  end

  defp call(:fetch_metadata, c, d, opts) do
    with {:ok, raw} <- api(c, :get, channel(d), nil, opts) do
      {:ok,
       compact(%{
         "id" => id(raw, "id"),
         "name" => field(raw, "name"),
         "topic" => field(raw, "topic"),
         "kind" => kind(field(raw, "type"))
       })}
    end
  end

  defp call(:open_dm, c, d, opts) do
    with {:ok, raw} <- api(c, :post, "/users/@me/channels", %{"recipient_id" => d["user_id"]}, opts),
         do: {:ok, %{"id" => id(raw, "id"), "kind" => "direct"}}
  end

  defp call(:create_thread, c, d, opts) do
    path =
      if d["parent_message_id"],
        do: channel(d) <> "/messages/#{d["parent_message_id"]}/threads",
        else: channel(d) <> "/threads"

    body = %{"name" => d["name"], "auto_archive_duration" => 1440, "type" => 11}
    with {:ok, raw} <- api(c, :post, path, body, opts), do: {:ok, thread(raw, d)}
  end

  defp call(:fetch_thread, c, d, opts) do
    with {:ok, raw} <- api(c, :get, "/channels/" <> d["thread_id"], nil, opts), do: {:ok, thread(raw, d)}
  end

  defp call(:fetch_messages, c, d, opts) do
    query =
      compact(%{
        "limit" => d["limit"] || 50,
        if(d["direction"] == "forward", do: "after", else: "before") => d["cursor"]
      })
      |> URI.encode_query()

    with {:ok, raw} when is_list(raw) <- api(c, :get, messages(d) <> "?" <> query, nil, opts),
         {:ok, values} <- map_messages(c, raw, d) do
      complete = length(raw) < (d["limit"] || 50)

      {:ok,
       %{
         "messages" => values,
         "complete" => complete,
         "next_cursor" => if(complete, do: nil, else: id(List.last(raw), "id"))
       }}
    end
  end

  defp call(:list_threads, _, %{"direction" => "forward"}, _), do: {:error, {:not_attempted, :unsupported_direction}}

  defp call(:list_threads, c, d, opts) do
    # Public archived threads are channel scoped. Active threads require a guild query.
    limit = min(d["limit"] || 50, 100)
    query = compact(%{"limit" => max(limit, 2), "before" => d["cursor"]}) |> URI.encode_query()

    with {:ok, raw} <- api(c, :get, channel(d) <> "/threads/archived/public?" <> query, nil, opts) do
      raw_threads = field(raw, "threads") || []
      threads = Enum.take(raw_threads, limit)
      more = field(raw, "has_more") == true or length(raw_threads) > limit
      cursor = if more, do: field(field(List.last(threads), "thread_metadata"), "archive_timestamp")
      {:ok, %{"threads" => Enum.map(threads, &thread(&1, d)), "complete" => not more, "next_cursor" => cursor}}
    end
  end

  defp call(:respond_interaction, c, d, opts) do
    case interaction_token(c, d, opts) do
      {:ok, token} ->
        ack(
          c,
          :post,
          "/interactions/#{d["interaction_id"]}/#{token}/callback",
          compact(%{"type" => d["response_type"], "data" => d["data"]}),
          opts
        )

      error ->
        error
    end
  end

  defp call(:send_file, c, d, opts) do
    with {:ok, bytes, filename} <- file_bytes(c, d["source"], opts),
         {:ok, raw} <-
           api(
             c,
             :post,
             messages(d),
             {:multipart, text_payload(Map.put(d, "text", d["caption"])), bytes, filename},
             opts
           ) do
      message_result(c, raw, "sent", d)
    end
  end

  defp call(:download_file, c, d, opts) do
    with {:ok, bytes, _} <- file_bytes(c, d["resource_ref"], opts),
         do: {:ok, %{"content_base64" => Base.encode64(bytes)}}
  end

  defp call(_, _, _, _), do: {:error, {:not_attempted, :unsupported}}

  defp file_bytes(_, %{"content_base64" => value, "filename" => name}, _) do
    with {:ok, bytes} <- Base.decode64(value), do: {:ok, bytes, name}
  end

  defp file_bytes(c, %{"client_id" => client_id, "id" => "discord://attachment/" <> path}, opts)
       when client_id == c.id do
    with [room, message, attachment] <- String.split(path, "/"),
         :ok <- Dependencies.req(),
         {:ok, raw} <- api(c, :get, "/channels/#{room}/messages/#{message}", nil, opts),
         item when is_map(item) <- Enum.find(field(raw, "attachments") || [], &(id(&1, "id") == attachment)),
         {:ok, bytes} <- download(field(item, "url"), opts) do
      {:ok, bytes, field(item, "filename") || "file"}
    else
      {:error, _} = error -> error
      _ -> {:error, {:not_attempted, :invalid_media_reference}}
    end
  end

  defp file_bytes(_, %{"kind" => "file", "id" => path}, _) do
    with {:ok, bytes} <- File.read(path), do: {:ok, bytes, Path.basename(path)}
  end

  defp file_bytes(_, _, _), do: {:error, {:not_attempted, :invalid_media_reference}}

  defp download(url, opts) do
    uri = URI.parse(url)

    if uri.scheme == "https" and uri.host in ["cdn.discordapp.com", "media.discordapp.net"] do
      case Req.get(
             [url: url, decode_body: false, redirect: false, retry: false] ++
               Keyword.take(opts, [:adapter, :plug, :finch_private])
           ) do
        {:ok, %{status: 200, body: bytes}} when is_binary(bytes) -> {:ok, bytes}
        _ -> {:error, :download_failed}
      end
    else
      {:error, {:not_attempted, :invalid_media_reference}}
    end
  end

  defp map_messages(c, raw, d) do
    Enum.reduce_while(raw, {:ok, []}, fn item, {:ok, acc} ->
      case message_result(c, item, "received", d) do
        {:ok, value} -> {:cont, {:ok, acc ++ [value]}}
        _ -> {:halt, {:error, :invalid_provider_result}}
      end
    end)
  end

  defp message_result(client, raw, status, request) do
    raw = if request["thread_id"], do: Map.put(raw, "parent_id", request["room_id"]), else: raw
    Normalizer.message(client, raw, status)
  end

  defp text_payload(d) do
    compact(%{
      "content" => d["text"],
      "message_reference" => if(d["reply_to_id"], do: %{"message_id" => d["reply_to_id"]}),
      "components" => keyboard(d["keyboard"]),
      "allowed_mentions" => %{"parse" => []}
    })
  end

  defp keyboard(nil), do: nil

  defp keyboard(%{"rows" => rows}) do
    Enum.map(rows, fn row ->
      %{
        "type" => 1,
        "components" =>
          Enum.map(row, fn button ->
            compact(%{
              "type" => 2,
              "style" => if(button["url"], do: 5, else: 1),
              "label" => button["text"],
              "custom_id" => button["value"],
              "url" => button["url"]
            })
          end)
      }
    end)
  end

  defp interaction_token(c, d, opts) do
    case opts[:interaction] do
      nil -> {:error, {:not_attempted, :missing_interaction_token}}
      private -> Jido.Chat.Discord.Interaction.token(c, d, private)
    end
  end

  defp thread(raw, d),
    do:
      compact(%{
        "id" => id(raw, "id"),
        "room_id" => id(raw, "parent_id") || d["room_id"],
        "name" => field(raw, "name") || d["name"],
        "parent_message_id" => d["parent_message_id"],
        "delivery_room_ref" => id(raw, "id")
      })

  defp kind(1), do: "direct"
  defp kind(3), do: "group"
  defp kind(type) when type in [10, 11, 12], do: "thread"
  defp kind(_), do: "channel"
  defp channel(d), do: "/channels/" <> (d["thread_id"] || d["room_id"])
  defp messages(d), do: channel(d) <> "/messages"
  defp message_path(d), do: messages(d) <> "/" <> d["message_id"]
  defp api(c, method, path, body, opts), do: c.transport.call(c.credentials.token, method, path, body, opts)

  defp ack(c, method, path, body, opts) do
    with {:ok, _} <- api(c, method, path, body, opts), do: {:ok, %{"acknowledged" => true}}
  end
end
