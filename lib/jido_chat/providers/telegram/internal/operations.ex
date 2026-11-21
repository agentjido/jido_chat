defmodule Jido.Chat.Telegram.Operations do
  @moduledoc false
  alias Jido.Chat.Client
  alias Jido.Chat.Providers.Dependencies
  alias Jido.Chat.Telegram.Adapter
  alias Jido.Chat.Telegram.Transport.ExGramClient

  @media_methods %{
    send_photo: {"sendPhoto", "photo"},
    send_document: {"sendDocument", "document"},
    send_sticker: {"sendSticker", "sticker"},
    send_animation: {"sendAnimation", "animation"},
    send_video_note: {"sendVideoNote", "video_note"}
  }

  @doc false
  def invoke(operation, %Client{adapter: Adapter, credentials: %{token: token}} = client, signal, opts)
      when is_binary(token) and token != "" do
    options = Keyword.merge(client.config, opts)

    legacy = [
      :reply_markup,
      :parse_mode,
      :rich_format,
      :caption,
      :format,
      :thread_id,
      :reply_to_id,
      :reply_to_message_id,
      :external_thread_id,
      :fallback_to_dm,
      :supports_forum_topics
    ]

    cond do
      Enum.any?(legacy, &Keyword.has_key?(options, &1)) ->
        {:error, {:not_attempted, :invalid_options}}

      true ->
        with :ok <- check_transport(client.transport) do
          if operation == :stream_text do
            Jido.Chat.Telegram.Streaming.run(client, signal, options)
          else
            call(operation, client, signal.data, options)
          end
        end
    end
  end

  def invoke(_, %Client{adapter: Adapter}, _, _), do: {:error, {:not_attempted, :missing_token}}
  def invoke(_, %Client{}, _, _), do: {:error, {:not_attempted, :unsupported}}

  defp check_transport(ExGramClient), do: Dependencies.telegram()
  defp check_transport(_transport), do: :ok

  @doc false
  def classify({:error, %{__struct__: ExGram.Error, code: :response_status_not_match, message: body}} = error)
      when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"error_code" => code} = body} when code in 400..499 ->
        category =
          case code do
            401 -> :unauthorized
            403 -> :forbidden
            404 -> :not_found
            429 -> :rate_limited
            _ -> :provider_failure
          end

        hints =
          case get_in(body, ["parameters", "retry_after"]) do
            seconds when is_integer(seconds) and seconds >= 0 -> %{retry_after_ms: seconds * 1000}
            _ -> %{}
          end

        {:error, {:rejected, category, hints}}

      _ ->
        error
    end
  end

  def classify(result), do: result

  defp call(:send_message, client, data, opts) do
    {method, payload} = text_request(data, "sendMessage", "sendRichMessage")

    with {:ok, raw} <- transport(client, method, payload, opts),
         {:ok, message} <- message(raw, "sent") do
      {:ok, message}
    end
  end

  defp call(:edit_message, client, data, opts) do
    {_, payload} = text_request(data, "editMessageText", "editMessageText")
    payload = Map.put(payload, "message_id", data["message_id"])

    with {:ok, raw} <- transport(client, "editMessageText", payload, opts),
         {:ok, message} <- message(raw, "updated") do
      {:ok, message}
    end
  end

  defp call(:delete_message, client, data, opts),
    do: acknowledge(client, "deleteMessage", %{"chat_id" => data["room_id"], "message_id" => data["message_id"]}, opts)

  defp call(:start_typing, client, data, opts) do
    payload =
      %{"chat_id" => data["room_id"], "action" => "typing"}
      |> optional("message_thread_id", data["thread_id"])

    acknowledge(client, "sendChatAction", payload, opts)
  end

  defp call(operation, client, data, opts) when operation in [:add_reaction, :remove_reaction] do
    reaction = if operation == :add_reaction, do: [%{"type" => "emoji", "emoji" => data["reaction"]}], else: []

    acknowledge(
      client,
      "setMessageReaction",
      %{"chat_id" => data["room_id"], "message_id" => data["message_id"], "reaction" => reaction},
      opts
    )
  end

  defp call(:fetch_metadata, client, data, opts) do
    with {:ok, chat} <- transport(client, "getChat", %{"chat_id" => data["room_id"]}, opts) do
      {:ok,
       %{"id" => identifier(field(chat, "id")), "kind" => conversation_kind(field(chat, "type"))}
       |> optional("name", field(chat, "title") || field(chat, "username") || field(chat, "first_name"))}
    end
  end

  defp call(:open_dm, client, data, opts) do
    with {:ok, chat} <- transport(client, "getChat", %{"chat_id" => data["user_id"]}, opts) do
      if field(chat, "type") == "private" and identifier(field(chat, "id")) == data["user_id"],
        do: {:ok, %{"id" => data["user_id"], "kind" => "direct"}},
        else: {:error, {:rejected, :not_found}}
    end
  end

  defp call(:create_thread, client, data, opts) do
    with {:ok, topic} <-
           transport(
             client,
             "createForumTopic",
             %{"chat_id" => data["room_id"], "name" => data["name"]},
             opts
           ) do
      {:ok,
       %{
         "id" => identifier(field(topic, "message_thread_id")),
         "room_id" => data["room_id"],
         "name" => field(topic, "name") || data["name"]
       }}
    end
  end

  defp call(:send_file, client, data, opts) do
    operation = if data["media_kind"] == "image", do: :send_photo, else: :send_document

    with {:ok, result} <- upload(operation, client, data, opts) do
      kind = if operation == :send_photo, do: "image", else: "file"

      {:ok,
       %{
         "id" => result["id"],
         "room_id" => result["room_id"],
         "status" => "sent",
         "media" => [%{"kind" => kind, "resource_ref" => result["resource_ref"]}]
       }
       |> optional("text", data["caption"])}
    end
  end

  defp call(operation, client, data, opts) when is_map_key(@media_methods, operation),
    do: upload(operation, client, data, opts)

  defp call(:get_file, client, data, opts), do: resolve_file(client, data["resource_ref"], opts)

  defp call(:download_file, client, data, opts) do
    with {:ok, file} <- resolve_file(client, data["resource_ref"], opts),
         {:ok, bytes} when is_binary(bytes) <-
           transport(client, "downloadFile", %{"file_path" => file["file_path"]}, opts) do
      {:ok, %{"content_base64" => Base.encode64(bytes)}}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_provider_result}
    end
  end

  defp call(:send_poll, client, data, opts) do
    payload =
      %{
        "chat_id" => data["room_id"],
        "question" => data["question"],
        "options" => Enum.map(data["options"], &%{"text" => &1})
      }
      |> optional("message_thread_id", data["thread_id"])
      |> optional("is_anonymous", data["is_anonymous"])
      |> routing(data)

    with {:ok, message} <- transport(client, "sendPoll", payload, opts) do
      {:ok,
       %{
         "id" => identifier(field(message, "message_id")),
         "room_id" => identifier(field(field(message, "chat"), "id")),
         "poll_id" => identifier(field(field(message, "poll"), "id"))
       }}
    end
  end

  defp call(:get_me, client, _data, opts) do
    with {:ok, user} <- transport(client, "getMe", %{}, opts) do
      {:ok,
       %{"id" => identifier(field(user, "id")), "is_bot" => field(user, "is_bot")}
       |> optional("username", field(user, "username"))
       |> optional("display_name", field(user, "first_name"))}
    end
  end

  defp call(:answer_callback_query, client, data, opts) do
    payload =
      %{"callback_query_id" => data["interaction_id"]}
      |> optional("text", data["text"])
      |> optional("show_alert", data["show_alert"])

    with {:ok, true} <- transport(client, "answerCallbackQuery", payload, opts) do
      {:ok, %{"answered" => true, "interaction_id" => data["interaction_id"]}}
    end
  end

  defp call(:send_draft, client, data, opts) do
    {method, payload} = text_request(data, "sendMessageDraft", "sendRichMessageDraft")
    payload = payload |> Map.put("chat_id", String.to_integer(data["room_id"])) |> Map.put("draft_id", data["draft_id"])

    with {:ok, true} <- transport(client, method, payload, opts) do
      {:ok, %{"acknowledged" => true, "draft_id" => data["draft_id"]}}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_provider_result}
    end
  end

  defp call(:set_webhook, client, data, opts) do
    payload =
      Map.take(data, ["url", "allowed_updates", "max_connections", "drop_pending_updates"])
      |> optional("secret_token", client.credentials[:secret_token])

    acknowledge(client, "setWebhook", payload, opts)
  end

  defp call(:delete_webhook, client, data, opts),
    do: acknowledge(client, "deleteWebhook", Map.take(data, ["drop_pending_updates"]), opts)

  defp call(:get_webhook_info, client, _data, opts) do
    with {:ok, info} <- transport(client, "getWebhookInfo", %{}, opts) do
      {:ok,
       %{
         "url" => field(info, "url"),
         "pending_update_count" => field(info, "pending_update_count"),
         "has_custom_certificate" => field(info, "has_custom_certificate")
       }}
    end
  end

  defp call(:fetch_updates, client, data, opts) do
    payload = Map.take(data, ["offset", "limit", "timeout", "allowed_updates"])

    with {:ok, updates} when is_list(updates) <- transport(client, "getUpdates", payload, opts),
         {:ok, delivery} <- Jido.Chat.normalize(client, updates) do
      signals =
        Enum.map(delivery.signals, fn signal ->
          {:ok, json} = Jido.Signal.Codec.serialize(signal)
          Jason.decode!(json)
        end)

      ids = Enum.map(updates, &field(&1, "update_id")) |> Enum.filter(&is_integer/1)
      next_offset = if ids == [], do: data["offset"], else: Enum.max(ids) + 1
      {:ok, %{"delivery_id" => delivery.id, "signals" => signals, "next_offset" => next_offset}}
    end
  end

  defp call(_, _, _, _), do: {:error, {:not_attempted, :unsupported}}

  defp text_request(data, plain_method, rich_method) do
    payload = %{"chat_id" => data["room_id"]} |> routing(data)

    if data["format"] in ["markdown", "html"] do
      {rich_method, Map.put(payload, "rich_message", %{data["format"] => data["text"]})}
    else
      {plain_method, Map.put(payload, "text", data["text"])}
    end
  end

  defp routing(payload, data) do
    payload
    |> optional("message_thread_id", data["thread_id"])
    |> optional("reply_parameters", if(data["reply_to_id"], do: %{"message_id" => data["reply_to_id"]}))
    |> optional("reply_markup", keyboard(data["keyboard"]))
  end

  defp keyboard(nil), do: nil

  defp keyboard(%{"rows" => rows}) do
    %{
      "inline_keyboard" =>
        Enum.map(rows, fn row ->
          Enum.map(row, fn button ->
            %{"text" => button["text"]} |> optional("callback_data", button["value"]) |> optional("url", button["url"])
          end)
        end)
    }
  end

  defp upload(operation, client, data, opts) do
    {method, key} = Map.fetch!(@media_methods, operation)

    payload =
      %{"chat_id" => data["room_id"], key => file_source(data["source"])}
      |> optional("caption", data["caption"])
      |> optional("parse_mode", caption_format(data["format"]))
      |> routing(data)

    with {:ok, raw} <- transport(client, method, payload, opts),
         {:ok, message} <- message(raw, "sent") do
      media = field(raw, key)
      media = if is_list(media), do: List.last(media), else: media

      result = %{
        "id" => message["id"],
        "room_id" => message["room_id"],
        "resource_ref" => reference(client, field(media, "file_id"))
      }

      case Zoi.parse(Jido.Chat.Telegram.Signal.Schemas.media_result(), result) do
        {:ok, result} -> {:ok, result}
        _ -> {:error, :invalid_provider_result}
      end
    end
  end

  defp resolve_file(client, ref, opts) do
    if ref["kind"] == "media" do
      with {:ok, file} <- transport(client, "getFile", %{"file_id" => file_id(ref["id"])}, opts) do
        result =
          %{"resource_ref" => reference(client, field(file, "file_id")), "file_path" => field(file, "file_path")}
          |> optional("size", field(file, "file_size"))

        case Zoi.parse(Jido.Chat.Telegram.Signal.Schemas.file_result(), result) do
          {:ok, checked} -> {:ok, checked}
          _ -> {:error, :invalid_provider_result}
        end
      end
    else
      {:error, {:not_attempted, :invalid_media_reference}}
    end
  end

  defp message(raw, status) do
    result =
      %{
        "id" => identifier(field(raw, "message_id")),
        "room_id" => identifier(field(field(raw, "chat"), "id")),
        "status" => status
      }
      |> optional("text", field(raw, "text") || field(raw, "caption"))
      |> optional("thread_id", identifier(field(raw, "message_thread_id")))
      |> optional("reply_to_id", identifier(field(field(raw, "reply_to_message"), "message_id")))

    case Zoi.parse(Jido.Chat.Signal.Schemas.result(:message), result) do
      {:ok, result} -> {:ok, result}
      _ -> {:error, :invalid_provider_result}
    end
  end

  defp acknowledge(client, method, payload, opts) do
    case transport(client, method, payload, opts) do
      {:ok, true} -> {:ok, %{"acknowledged" => true}}
      {:error, _} = error -> error
      _ -> {:error, :invalid_provider_result}
    end
  end

  defp transport(client, method, payload, opts),
    do: classify(client.transport.call(client.credentials.token, method, payload, opts))

  defp file_source(%{"content_base64" => content, "filename" => filename}),
    do: {:file_content, Base.decode64!(content), filename}

  defp file_source(%{"kind" => "file", "id" => path}), do: {:file, path}
  defp file_source(%{"id" => id}), do: file_id(id)
  defp file_id("telegram://file/" <> id), do: id
  defp file_id(id), do: id
  defp caption_format("html"), do: "HTML"
  defp caption_format("markdown"), do: "MarkdownV2"
  defp caption_format(_), do: nil
  defp conversation_kind("private"), do: "direct"
  defp conversation_kind(value) when value in ["group", "supergroup"], do: "group"
  defp conversation_kind("channel"), do: "channel"
  defp conversation_kind(_), do: "unknown"

  defp reference(client, id),
    do: %{"client_id" => client.id, "id" => if(id, do: "telegram://file/" <> to_string(id)), "kind" => "media"}

  defp field(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        case Enum.find(Map.to_list(map), fn {atom, _value} -> is_atom(atom) and Atom.to_string(atom) == key end) do
          {_, value} -> value
          nil -> nil
        end
    end
  end

  defp field(_, _), do: nil
  defp identifier(nil), do: nil
  defp identifier(value), do: to_string(value)
  defp optional(map, _, nil), do: map
  defp optional(map, key, value), do: Map.put(map, key, value)
end
