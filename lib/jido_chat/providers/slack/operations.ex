defmodule Jido.Chat.Slack.Operations do
  @moduledoc false

  alias Jido.Chat.{Client, Signal}
  alias Jido.Chat.Providers.Dependencies
  alias Jido.Chat.Slack.{Adapter, Renderer, Transport.ReqClient}

  @doc false
  @spec invoke(atom(), Client.t(), Jido.Signal.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def invoke(:load_options, %Client{adapter: Adapter} = client, request, opts) do
    call(:load_options, client, nil, request.data, Keyword.merge(client.config, opts))
  end

  def invoke(
        operation,
        %Client{adapter: Adapter, credentials: %{bot_token: token}} = client,
        request,
        opts
      )
      when is_binary(token) and token != "" do
    opts = Keyword.merge(client.config, opts)

    with :ok <- check_transport(client.transport, opts) do
      call(operation, client, token, request.data, opts)
    end
  end

  def invoke(_, %Client{adapter: Adapter}, _, _),
    do: {:error, {:not_attempted, :missing_bot_token}}

  def invoke(_, _, _, _), do: {:error, {:not_attempted, :unsupported}}

  defp check_transport(ReqClient, opts), do: Dependencies.req(Keyword.get(opts, :req, Req))
  defp check_transport(_custom, _opts), do: :ok

  defp call(:stream_text, client, token, data, opts) do
    case Jido.Chat.Adapter.render_stream(opts[:stream]) do
      text when is_binary(text) -> send_message(client, token, data, text, opts)
      _ -> {:error, :invalid_stream}
    end
  end

  defp call(:send_message, client, token, data, opts),
    do: send_message(client, token, data, data["text"], opts)

  defp call(:send_file, client, token, data, opts) do
    room_id = data["room_id"]
    opts = message_options(data, opts)

    with {:ok, upload} <- upload(client, data["source"], data),
         {:ok, raw} <- client.transport.send_file(token, room_id, upload, opts) do
      file_message(raw, room_id, data["caption"] || "")
    end
  end

  defp call(:edit_message, client, token, data, opts) do
    opts = render_options(opts, data)

    with {:ok, raw} <-
           client.transport.edit_message(
             token,
             data["room_id"],
             data["message_id"],
             data["text"],
             opts
           ) do
      message(raw, data["room_id"], "updated")
    end
  end

  defp call(:delete_message, client, token, data, opts),
    do: acknowledge(client.transport.delete_message(token, data["room_id"], data["message_id"], opts))

  defp call(:start_typing, _, _, _, _), do: {:error, {:not_attempted, :unsupported}}

  defp call(:fetch_metadata, client, token, data, opts) do
    with {:ok, channel} <- client.transport.fetch_metadata(token, data["room_id"], opts) do
      conversation(channel, data["room_id"])
    end
  end

  defp call(:fetch_thread, client, token, data, opts) do
    with {:ok, _} <-
           client.transport.fetch_thread(token, data["room_id"], data["thread_id"], opts) do
      result(:thread, %{
        "id" => data["thread_id"],
        "room_id" => data["room_id"],
        "parent_message_id" => data["thread_id"]
      })
    end
  end

  defp call(:fetch_message, client, token, data, opts) do
    with {:ok, raw} <-
           client.transport.fetch_message(token, data["room_id"], data["message_id"], opts) do
      message(raw, data["room_id"], "received")
    end
  end

  defp call(:get_user, client, token, data, opts) do
    with {:ok, raw} <- client.transport.get_user(token, data["user_id"], opts) do
      user(raw, data["user_id"])
    end
  end

  defp call(:fetch_subject, client, token, data, opts) do
    case data["thread_id"] do
      thread_id when is_binary(thread_id) and thread_id != "" ->
        with {:ok, raw} <-
               client.transport.fetch_message(
                 token,
                 data["room_id"],
                 thread_id,
                 Keyword.put(opts, :thread_ts, thread_id)
               ) do
          %{"id" => thread_id, "room_id" => data["room_id"], "kind" => "thread"}
          |> optional("title", present(raw["text"]))
          |> result(:subject)
        end

      _ ->
        with {:ok, channel} <- client.transport.fetch_metadata(token, data["room_id"], opts) do
          %{"id" => data["room_id"], "room_id" => data["room_id"], "kind" => "conversation"}
          |> optional("title", channel_title(channel))
          |> result(:subject)
        end
    end
  end

  defp call(:get_thread_participants, client, token, data, opts) do
    with {:ok, ids} <- participant_ids(client, token, data, opts),
         {:ok, users} <- participant_users(client, token, ids, opts) do
      result(:participants, %{
        "participants" => users,
        "complete" => true,
        "scope" => "all",
        "next_cursor" => nil
      })
    end
  end

  defp call(:mark_as_read, client, token, data, opts),
    do: acknowledge(client.transport.mark_as_read(token, data["room_id"], data["message_id"], opts))

  defp call(:download_file, client, token, data, opts) do
    reference = data["resource_ref"]
    url = reference["id"]

    with true <- reference["client_id"] == client.id,
         true <- reference["kind"] == "media",
         true <- trusted_download_url?(url),
         {:ok, bytes} when is_binary(bytes) <-
           client.transport.download_file(token, url, opts) do
      result(:resource, %{"content_base64" => Base.encode64(bytes)})
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_resource_reference}
    end
  end

  defp call(:add_reaction, client, token, data, opts),
    do:
      acknowledge(
        client.transport.add_reaction(
          token,
          data["room_id"],
          data["message_id"],
          data["reaction"],
          opts
        )
      )

  defp call(:remove_reaction, client, token, data, opts),
    do:
      acknowledge(
        client.transport.remove_reaction(
          token,
          data["room_id"],
          data["message_id"],
          data["reaction"],
          opts
        )
      )

  defp call(:post_ephemeral, client, token, data, opts) do
    opts = message_options(data, opts)

    with {:ok, raw} <-
           client.transport.post_ephemeral(
             token,
             data["room_id"],
             data["user_id"],
             data["text"],
             opts
           ) do
      message(raw, data["room_id"], "sent")
    end
  end

  defp call(:open_modal, client, token, data, opts) do
    trigger_id = opts[:trigger_id]

    with true <- is_binary(trigger_id) and trigger_id != "",
         {:ok, view} <- Renderer.modal(data["modal"]),
         {:ok, raw} <- client.transport.open_modal(token, trigger_id, view, opts) do
      result(:modal, %{"opened" => true, "id" => get_in(raw, ["view", "id"])})
    else
      false -> {:error, {:not_attempted, :missing_trigger_id}}
      error -> error
    end
  end

  defp call(:load_options, _client, _token, data, opts) do
    with {:ok, loader} <- options_loader(opts),
         {:ok, value} <- invoke_loader(loader, data, opts),
         {:ok, canonical} <- canonical_options(value, data["limit"]) do
      result(:options, canonical)
    end
  end

  defp call(:fetch_messages, client, token, data, opts) do
    if data["direction"] in [nil, "backward"] do
      query =
        opts
        |> Keyword.put(:limit, data["limit"] || 50)
        |> Keyword.put(:cursor, data["cursor"])
        |> optional_keyword(:thread_ts, data["thread_id"])

      with {:ok, raw} <- client.transport.fetch_messages(token, data["room_id"], query),
           {:ok, messages} <- messages(raw["messages"], data["room_id"]) do
        cursor = next_cursor(raw)

        result(:message_page, %{
          "messages" => messages,
          "next_cursor" => cursor,
          "complete" => is_nil(cursor)
        })
      end
    else
      {:error, :unsupported_direction}
    end
  end

  defp call(:list_threads, client, token, data, opts) do
    query = Keyword.merge(opts, limit: data["limit"] || 50, cursor: data["cursor"])

    with {:ok, raw} <- client.transport.list_threads(token, data["room_id"], query),
         {:ok, threads} <- threads(raw["threads"], data["room_id"]) do
      cursor = next_cursor(raw)

      result(:thread_page, %{
        "threads" => threads,
        "next_cursor" => cursor,
        "complete" => is_nil(cursor)
      })
    end
  end

  defp call(:open_dm, client, token, data, opts) do
    with {:ok, id} <- client.transport.open_dm(token, data["user_id"], opts) do
      result(:conversation, %{"id" => to_string(id), "kind" => "direct"})
    end
  end

  defp call(_, _, _, _, _), do: {:error, {:not_attempted, :unsupported}}

  defp send_message(client, token, data, text, opts) do
    opts = message_options(data, opts)

    with {:ok, raw} <- client.transport.send_message(token, data["room_id"], text, opts) do
      message(raw, data["room_id"], "sent")
    end
  end

  defp upload(_client, %{"content_base64" => encoded, "filename" => filename}, data) do
    with {:ok, bytes} <- Base.decode64(encoded) do
      {:ok,
       %{
         body: bytes,
         filename: filename,
         title: filename,
         alt_text: data["caption"]
       }}
    end
  end

  defp upload(client, %{"id" => id, "client_id" => client_id, "kind" => "url"}, _data)
       when client_id == client.id,
       do: {:error, {:not_attempted, {:unsupported_file_reference, id}}}

  defp upload(_, _, _), do: {:error, :invalid_resource_reference}

  defp message(raw, room_id, status) when is_map(raw) do
    nested = if is_map(raw["message"]), do: raw["message"], else: %{}
    id = raw["ts"] || raw["message_ts"] || nested["ts"]
    channel = raw["channel"] || nested["channel"] || room_id

    %{"id" => identifier(id), "room_id" => identifier(channel), "status" => status}
    |> optional("text", raw["text"] || nested["text"])
    |> optional("sender", actor(raw["user"] || nested["user"]))
    |> optional("thread_id", thread_id(raw["thread_ts"] || nested["thread_ts"], id))
    |> optional("timestamp", timestamp(id))
    |> result(:message)
  end

  defp message(_, _, _), do: {:error, :invalid_provider_result}

  defp file_message(raw, room_id, text) do
    file = List.first(raw["files"] || []) || %{}
    id = file_share_id(file, room_id) || file["id"]

    %{"id" => identifier(id), "room_id" => room_id, "status" => "sent"}
    |> optional("text", text)
    |> result(:message)
  end

  defp file_share_id(file, room_id) do
    shares = file["shares"] || %{}

    Enum.find_value(["public", "private"], fn kind ->
      shares |> get_in([kind, room_id]) |> List.wrap() |> List.first() |> then(&(&1 && &1["ts"]))
    end)
  end

  defp conversation(channel, fallback_id) do
    kind =
      cond do
        channel["is_im"] -> "direct"
        channel["is_mpim"] -> "group"
        true -> "channel"
      end

    %{"id" => identifier(channel["id"] || fallback_id), "kind" => kind}
    |> optional("name", present(channel["name"]))
    |> optional("topic", get_in(channel, ["topic", "value"]) |> present())
    |> result(:conversation)
  end

  defp user(raw, fallback_id) do
    profile = raw["profile"] || %{}

    %{"id" => identifier(raw["id"] || fallback_id)}
    |> optional("username", present(raw["name"]))
    |> optional("display_name", present(profile["display_name"]) || present(profile["real_name"]))
    |> optional("is_bot", boolean(raw["is_bot"]))
    |> result(:user)
  end

  defp participant_ids(client, token, data, opts) do
    max_pages = opts[:max_pages] || 10
    collect_participants(client, token, data["room_id"], data["thread_id"], opts, nil, max_pages, MapSet.new())
  end

  defp collect_participants(_, _, _, _, _, _, 0, _),
    do: {:error, :participant_page_limit_exceeded}

  defp collect_participants(client, token, room_id, thread_id, opts, cursor, pages, ids) do
    page_opts = Keyword.merge(opts, cursor: cursor, limit: opts[:page_size] || 100)

    with {:ok, raw} <- client.transport.fetch_thread(token, room_id, thread_id, page_opts) do
      ids =
        Enum.reduce(raw["messages"] || [], ids, fn message, result ->
          case message["user"] || message["bot_id"] do
            id when is_binary(id) and id != "" -> MapSet.put(result, id)
            _ -> result
          end
        end)

      case next_cursor(raw) do
        nil -> {:ok, MapSet.to_list(ids) |> Enum.sort()}
        next -> collect_participants(client, token, room_id, thread_id, opts, next, pages - 1, ids)
      end
    end
  end

  defp participant_users(client, token, ids, opts) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, users} ->
      case client.transport.get_user(token, id, opts) do
        {:ok, raw} ->
          case user(raw, id) do
            {:ok, value} -> {:cont, {:ok, [value | users]}}
            error -> {:halt, error}
          end

        error ->
          if String.starts_with?(id, "B") do
            {:cont, {:ok, [%{"id" => id, "is_bot" => true} | users]}}
          else
            {:halt, error}
          end
      end
    end)
    |> case do
      {:ok, users} -> {:ok, Enum.reverse(users)}
      error -> error
    end
  end

  defp messages(items, room_id) when is_list(items) do
    map_results(items, &message(&1, room_id, "received"))
  end

  defp messages(_, _), do: {:error, :invalid_provider_result}

  defp threads(items, room_id) when is_list(items) do
    map_results(items, fn item ->
      id = item["thread_ts"] || item["ts"]

      %{"id" => identifier(id), "room_id" => room_id, "parent_message_id" => identifier(id)}
      |> optional("name", present(item["text"]))
      |> result(:thread)
    end)
  end

  defp threads(_, _), do: {:error, :invalid_provider_result}

  defp map_results(items, mapper) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, values} ->
      case mapper.(item) do
        {:ok, value} -> {:cont, {:ok, [value | values]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp message_options(data, opts) do
    opts
    |> render_options(data)
    |> optional_keyword(:thread_ts, data["thread_id"] || data["reply_to_id"])
  end

  defp render_options(opts, data) do
    case keyboard_blocks(data["keyboard"]) do
      [] -> opts
      blocks -> Keyword.put(opts, :blocks, blocks)
    end
  end

  defp keyboard_blocks(%{"rows" => rows}) do
    Enum.map(rows, fn row ->
      %{
        "type" => "actions",
        "elements" =>
          Enum.map(row, fn button ->
            %{"type" => "button", "text" => %{"type" => "plain_text", "text" => button["text"]}}
            |> optional("action_id", button["value"])
            |> optional("value", button["value"])
            |> optional("url", button["url"])
          end)
      }
    end)
  end

  defp keyboard_blocks(_), do: []

  defp options_loader(opts) do
    case opts[:options_loader] do
      loader when is_function(loader, 1) or is_function(loader, 2) -> {:ok, loader}
      {module, function, args} = loader when is_atom(module) and is_atom(function) and is_list(args) -> {:ok, loader}
      _ -> {:error, {:not_attempted, :missing_options_loader}}
    end
  end

  defp invoke_loader(loader, data, _opts) when is_function(loader, 1), do: normalize_loader(loader.(data))
  defp invoke_loader(loader, data, opts) when is_function(loader, 2), do: normalize_loader(loader.(data, opts))

  defp invoke_loader({module, function, args}, data, _opts),
    do: normalize_loader(apply(module, function, args ++ [data]))

  defp normalize_loader({:ok, value}), do: {:ok, value}
  defp normalize_loader({:error, _} = error), do: error
  defp normalize_loader(value), do: {:ok, value}

  defp canonical_options(%{"options" => options} = value, limit) when is_list(options) do
    options = if is_integer(limit), do: Enum.take(options, limit), else: options

    {:ok,
     %{
       "options" => Enum.map(options, &option/1),
       "option_groups" => value["option_groups"],
       "complete" => value["complete"] != false
     }
     |> compact()}
  rescue
    _ -> {:error, :invalid_options_result}
  end

  defp canonical_options(options, limit) when is_list(options),
    do: canonical_options(%{"options" => options}, limit)

  defp canonical_options(_, _), do: {:error, :invalid_options_result}

  defp option(%{"label" => label, "value" => value} = option),
    do: Map.take(option, ["label", "value", "description", "url"]) |> Map.merge(%{"label" => label, "value" => value})

  defp option(%{label: label, value: value} = option),
    do: option(%{"label" => to_string(label), "value" => to_string(value), "description" => option[:description]})

  defp option({label, value}), do: %{"label" => to_string(label), "value" => to_string(value)}

  defp acknowledge({:ok, _}), do: {:ok, %{"acknowledged" => true}}
  defp acknowledge(error), do: error

  defp result(value, kind) when is_map(value), do: result(kind, value)

  defp result(kind, value) do
    case Zoi.parse(Signal.Schemas.result(kind), compact(value)) do
      {:ok, checked} -> {:ok, checked}
      _ -> {:error, :invalid_provider_result}
    end
  end

  defp next_cursor(raw), do: present(get_in(raw, ["response_metadata", "next_cursor"]))

  defp actor(nil), do: nil
  defp actor(id), do: %{"id" => identifier(id)}
  defp boolean(value) when is_boolean(value), do: value
  defp boolean(_), do: nil

  defp thread_id(value, id) do
    value = present(value)
    if value == identifier(id), do: nil, else: value
  end

  defp timestamp(nil), do: nil

  defp timestamp(value) do
    case Float.parse(to_string(value)) do
      {seconds, ""} ->
        seconds
        |> Kernel.*(1_000_000)
        |> round()
        |> DateTime.from_unix(:microsecond)
        |> case do
          {:ok, datetime} -> DateTime.to_iso8601(datetime)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp channel_title(channel),
    do: present(channel["name"]) || present(get_in(channel, ["topic", "value"]))

  defp trusted_download_url?(url) when is_binary(url) do
    uri = URI.parse(url)
    uri.scheme == "https" and uri.userinfo == nil and uri.host in ["files.slack.com", "files.slack-edge.com"]
  end

  defp trusted_download_url?(_), do: false

  defp optional_keyword(opts, _, nil), do: opts
  defp optional_keyword(opts, key, value), do: Keyword.put(opts, key, value)
  defp identifier(nil), do: nil
  defp identifier(value), do: to_string(value)
  defp present(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  defp present(_), do: nil
  defp optional(map, _, nil), do: map
  defp optional(map, key, value), do: Map.put(map, key, value)
  defp compact(map), do: Map.reject(map, fn {_, value} -> is_nil(value) end)
end
