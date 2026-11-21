defmodule Jido.Chat.Slack.Transport.ReqClient do
  @moduledoc "Req-based Slack Web API transport."

  @behaviour Jido.Chat.Slack.Transport

  @compile {:no_warn_undefined, Req.Response}

  alias Jido.Chat.Providers.Dependencies

  @base_url "https://slack.com/api"

  @impl true
  def send_message(token, channel_id, text, opts) do
    payload =
      %{"channel" => channel_id, "text" => text}
      |> Map.merge(keyword_payload(opts, [:blocks, :attachments, :thread_ts, :reply_broadcast]))
      |> Map.merge(keyword_payload(opts, [:unfurl_links, :unfurl_media, :username, :icon_emoji, :icon_url]))

    api_post(token, "chat.postMessage", payload, opts)
  end

  @impl true
  def send_file(token, channel_id, %{body: bytes, filename: filename} = upload, opts)
      when is_binary(bytes) and bytes != "" and is_binary(filename) and filename != "" do
    with {:ok, upload_result} <-
           api_post(
             token,
             "files.getUploadURLExternal",
             upload_url_payload(upload, filename, byte_size(bytes)),
             opts
           ),
         upload_url when is_binary(upload_url) <- upload_result["upload_url"],
         file_id when is_binary(file_id) <- upload_result["file_id"],
         :ok <- upload_external_file(upload_url, bytes, opts),
         {:ok, result} <-
           api_post(
             token,
             "files.completeUploadExternal",
             complete_upload_payload(channel_id, file_id, filename, upload, opts),
             opts
           ) do
      {:ok, result}
    else
      nil -> {:error, :invalid_upload_response}
      {:error, _} = error -> error
    end
  end

  def send_file(_, _, _, _), do: {:error, :missing_file_source}

  @impl true
  def edit_message(token, channel_id, message_id, text, opts) do
    payload =
      %{"channel" => channel_id, "ts" => message_id, "text" => text}
      |> Map.merge(keyword_payload(opts, [:blocks, :attachments]))

    api_post(token, "chat.update", payload, opts)
  end

  @impl true
  def delete_message(token, channel_id, message_id, opts) do
    acknowledge(api_post(token, "chat.delete", %{"channel" => channel_id, "ts" => message_id}, opts))
  end

  @impl true
  def fetch_metadata(token, channel_id, opts) do
    payload = %{
      "channel" => channel_id,
      "include_num_members" => Keyword.get(opts, :include_num_members, true)
    }

    with {:ok, result} <- api_post(token, "conversations.info", payload, opts),
         channel when is_map(channel) <- result["channel"] do
      {:ok, channel}
    else
      {:error, _} = error -> error
      _ -> {:error, :missing_channel}
    end
  end

  @impl true
  def fetch_thread(token, channel_id, thread_id, opts) do
    fetch_messages(token, channel_id, Keyword.put(opts, :thread_ts, thread_id))
  end

  @impl true
  def fetch_message(token, channel_id, message_id, opts) do
    case opts[:thread_ts] do
      thread_id when is_binary(thread_id) and thread_id != "" ->
        with {:ok, result} <- fetch_thread(token, channel_id, thread_id, opts),
             messages when is_list(messages) <- result["messages"],
             message when is_map(message) <- Enum.find(messages, &(&1["ts"] == message_id)) do
          {:ok, message}
        else
          {:error, _} = error -> error
          _ -> {:error, :not_found}
        end

      _ ->
        payload = %{
          "channel" => channel_id,
          "latest" => message_id,
          "inclusive" => true,
          "limit" => 1
        }

        with {:ok, result} <- api_post(token, "conversations.history", payload, opts),
             [%{"ts" => ^message_id} = message | _] <- result["messages"] || [] do
          {:ok, message}
        else
          {:error, _} = error -> error
          _ -> {:error, :not_found}
        end
    end
  end

  @impl true
  def get_user(token, user_id, opts) do
    with {:ok, result} <- api_post(token, "users.info", %{"user" => user_id}, opts),
         user when is_map(user) <- result["user"] do
      {:ok, user}
    else
      {:error, _} = error -> error
      _ -> {:error, :missing_user}
    end
  end

  @impl true
  def mark_as_read(token, channel_id, message_id, opts) do
    acknowledge(api_post(token, "conversations.mark", %{"channel" => channel_id, "ts" => message_id}, opts))
  end

  @impl true
  def download_file(token, url, opts) do
    request = [
      method: :get,
      url: url,
      headers: auth_headers(token, opts),
      redirect: true,
      decode_body: false
    ]

    case request(request, opts) do
      {:ok, %{__struct__: Req.Response, status: status, body: body} = response}
      when status in 200..299 and is_binary(body) ->
        if html_response?(response), do: {:error, :unexpected_html_response}, else: {:ok, body}

      {:ok, %{__struct__: Req.Response, status: status, body: body}} when status in 200..299 ->
        {:error, {:invalid_download_body, body}}

      {:ok, %{__struct__: Req.Response, status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def fetch_messages(token, channel_id, opts) do
    payload =
      %{"channel" => channel_id, "limit" => Keyword.get(opts, :limit, 50)}
      |> maybe_put("cursor", opts[:cursor])
      |> maybe_put("inclusive", opts[:inclusive])

    case opts[:thread_ts] do
      thread_id when is_binary(thread_id) and thread_id != "" ->
        api_post(token, "conversations.replies", Map.put(payload, "ts", thread_id), opts)

      _ ->
        api_post(token, "conversations.history", payload, opts)
    end
  end

  @impl true
  def list_threads(token, channel_id, opts) do
    with {:ok, result} <- fetch_messages(token, channel_id, Keyword.delete(opts, :thread_ts)) do
      {:ok,
       %{
         "threads" => Enum.filter(result["messages"] || [], &thread_root?/1),
         "response_metadata" => result["response_metadata"] || %{}
       }}
    end
  end

  @impl true
  def add_reaction(token, channel_id, message_id, emoji, opts) do
    reaction(token, "reactions.add", channel_id, message_id, emoji, opts)
  end

  @impl true
  def remove_reaction(token, channel_id, message_id, emoji, opts) do
    reaction(token, "reactions.remove", channel_id, message_id, emoji, opts)
  end

  @impl true
  def post_ephemeral(token, channel_id, user_id, text, opts) do
    payload =
      %{"channel" => channel_id, "user" => user_id, "text" => text}
      |> Map.merge(keyword_payload(opts, [:blocks, :attachments, :thread_ts]))

    api_post(token, "chat.postEphemeral", payload, opts)
  end

  @impl true
  def open_dm(token, user_id, opts) do
    with {:ok, result} <- api_post(token, "conversations.open", %{"users" => user_id}, opts),
         %{"id" => id} when is_binary(id) <- result["channel"] do
      {:ok, id}
    else
      {:error, _} = error -> error
      _ -> {:error, :missing_channel}
    end
  end

  @impl true
  def open_modal(token, trigger_id, payload, opts) do
    api_post(token, "views.open", %{"trigger_id" => trigger_id, "view" => payload}, opts)
  end

  defp reaction(token, method, channel_id, message_id, emoji, opts) do
    payload = %{
      "channel" => channel_id,
      "timestamp" => message_id,
      "name" => normalize_emoji_name(emoji)
    }

    acknowledge(api_post(token, method, payload, opts))
  end

  defp acknowledge({:ok, _}), do: {:ok, true}
  defp acknowledge(error), do: error

  defp api_post(token, method, payload, opts) do
    request = [
      method: :post,
      url: api_url(method, opts),
      headers: auth_headers(token, opts),
      form: encode_form(payload)
    ]

    case request(request, opts) do
      {:ok, %{__struct__: Req.Response, status: status, body: body}} when status in 200..299 ->
        normalize_response(body)

      {:ok, %{__struct__: Req.Response, status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_response(%{"ok" => true} = body), do: {:ok, body}

  defp normalize_response(%{"ok" => false, "error" => error} = body),
    do: {:error, {:slack_api_error, error, body}}

  defp normalize_response(body) when is_map(body), do: {:ok, body}
  defp normalize_response(other), do: {:error, {:invalid_response, other}}

  defp upload_url_payload(upload, filename, length) do
    %{"filename" => filename, "length" => length}
    |> maybe_put("alt_txt", upload[:alt_text])
  end

  defp complete_upload_payload(channel_id, file_id, filename, upload, opts) do
    %{
      "files" => [%{"id" => file_id, "title" => upload[:title] || filename}],
      "channel_id" => channel_id
    }
    |> maybe_put("initial_comment", opts[:caption] || opts[:initial_comment])
    |> maybe_put("thread_ts", opts[:thread_ts])
  end

  defp upload_external_file(url, bytes, opts) do
    request = [method: :post, url: url, headers: [{"content-type", "application/octet-stream"}], body: bytes]

    case request(request, opts) do
      {:ok, %{__struct__: Req.Response, status: status}} when status in 200..299 -> :ok
      {:ok, %{__struct__: Req.Response, status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp request(request, opts) do
    req_module = Keyword.get(opts, :req, Req)

    with :ok <- Dependencies.req(req_module) do
      req_module.request(request)
    end
  end

  defp html_response?(response) do
    response
    |> Req.Response.get_header("content-type")
    |> Enum.any?(
      &(String.starts_with?(String.downcase(&1), "text/html") or
          String.starts_with?(String.downcase(&1), "application/xhtml+xml"))
    )
  end

  defp api_url(method, opts) do
    String.trim_trailing(Keyword.get(opts, :base_url, @base_url), "/") <> "/" <> method
  end

  defp auth_headers(token, opts) do
    [{"authorization", "Bearer #{token}"}] ++ normalize_headers(opts[:headers])
  end

  defp encode_form(payload),
    do: Map.new(payload, fn {key, value} -> {key, encode_form_value(value)} end)

  defp encode_form_value(value) when is_map(value) or is_list(value), do: Jason.encode!(value)
  defp encode_form_value(value) when is_boolean(value) or is_number(value), do: to_string(value)
  defp encode_form_value(value), do: value

  defp keyword_payload(opts, keys) do
    Enum.reduce(keys, %{}, fn key, result ->
      case opts[key] do
        nil -> result
        value -> Map.put(result, Atom.to_string(key), value)
      end
    end)
  end

  defp thread_root?(message) do
    reply_count = message["reply_count"] || 0
    thread_id = message["thread_ts"]
    reply_count > 0 or (is_binary(thread_id) and thread_id == message["ts"])
  end

  defp normalize_emoji_name(":" <> rest), do: String.trim_trailing(rest, ":")
  defp normalize_emoji_name(emoji), do: emoji
  defp maybe_put(map, _, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
  defp normalize_headers(nil), do: []

  defp normalize_headers(headers) do
    Enum.map(headers, fn {key, value} -> {to_string(key), to_string(value)} end)
  end
end
