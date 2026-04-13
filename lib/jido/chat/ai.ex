defmodule Jido.Chat.AI do
  @moduledoc """
  Framework-agnostic conversion helpers for turning chat history into AI-ready messages.
  """

  alias Jido.Chat.{Media, Message}

  @type ai_content_part :: map()
  @type ai_message :: %{
          required(:role) => String.t(),
          required(:content) => String.t() | [ai_content_part()]
        }

  @doc "Converts normalized chat messages into AI-friendly role/content maps."
  @spec to_messages([Message.t() | map()], keyword()) :: [ai_message()]
  def to_messages(messages, opts \\ []) when is_list(messages) do
    messages
    |> Enum.map(&normalize_message/1)
    |> sort_messages()
    |> Enum.map(&to_ai_message(&1, opts))
  end

  @doc "Alias for `to_messages/2`."
  @spec to_ai_messages([Message.t() | map()], keyword()) :: [ai_message()]
  def to_ai_messages(messages, opts \\ []), do: to_messages(messages, opts)

  defp normalize_message(%Message{} = message), do: message
  defp normalize_message(message) when is_map(message), do: Message.new(message)

  defp sort_messages(messages) do
    messages
    |> Enum.with_index()
    |> Enum.sort_by(fn {message, index} -> {message_sort_key(message), index} end)
    |> Enum.map(&elem(&1, 0))
  end

  defp message_sort_key(%Message{created_at: %DateTime{} = dt}),
    do: DateTime.to_unix(dt, :microsecond)

  defp message_sort_key(%Message{created_at: %NaiveDateTime{} = dt}),
    do: NaiveDateTime.to_iso8601(dt)

  defp message_sort_key(%Message{created_at: created_at}) when is_integer(created_at),
    do: created_at

  defp message_sort_key(%Message{created_at: created_at}) when is_binary(created_at),
    do: created_at

  defp message_sort_key(_message), do: :infinity

  defp to_ai_message(%Message{} = message, opts) do
    parts =
      []
      |> maybe_add_text_part(message.text || message.formatted)
      |> Kernel.++(attachment_parts(message, opts))

    ai_message =
      %{
        role: role_for(message),
        content:
          if(length(parts) <= 1 and text_only_parts?(parts), do: single_text(parts), else: parts)
      }
      |> maybe_put_name(message, opts)

    transform_message(ai_message, message, opts)
  end

  defp maybe_add_text_part(parts, nil), do: parts
  defp maybe_add_text_part(parts, ""), do: parts
  defp maybe_add_text_part(parts, text), do: parts ++ [%{type: "text", text: text}]

  defp attachment_parts(%Message{attachments: attachments} = message, opts) do
    Enum.flat_map(attachments || [], fn
      %Media{} = attachment ->
        attachment_to_parts(attachment, message, opts)

      attachment when is_map(attachment) ->
        attachment |> Media.normalize() |> attachment_to_parts(message, opts)

      _other ->
        []
    end)
  end

  defp attachment_to_parts(%Media{kind: :image} = attachment, _message, _opts) do
    [
      %{
        type: "image",
        url: attachment.url,
        media_type: attachment.media_type,
        metadata: attachment.metadata || %{}
      }
    ]
  end

  defp attachment_to_parts(%Media{kind: :file} = attachment, message, opts) do
    if text_like_file?(attachment) do
      case resolve_file_text(attachment, opts) do
        nil ->
          unsupported_attachment_parts(attachment, message, opts)

        text ->
          [%{type: "text", text: text, filename: attachment.filename}]
      end
    else
      unsupported_attachment_parts(attachment, message, opts)
    end
  end

  defp attachment_to_parts(%Media{} = attachment, message, opts) do
    unsupported_attachment_parts(attachment, message, opts)
  end

  defp unsupported_attachment_parts(attachment, message, opts) do
    case opts[:unsupported_attachment] do
      nil ->
        []

      callback when is_function(callback, 2) ->
        case callback.(attachment, message) do
          nil -> []
          :skip -> []
          value when is_binary(value) -> [%{type: "text", text: value}]
          value when is_map(value) -> [value]
          values when is_list(values) -> values
          _other -> []
        end

      _other ->
        []
    end
  end

  defp resolve_file_text(%Media{metadata: metadata} = attachment, opts) do
    case metadata[:data] || metadata["data"] do
      data when is_binary(data) ->
        data

      _ ->
        case opts[:fetch_attachment] do
          callback when is_function(callback, 1) ->
            case callback.(attachment) do
              {:ok, value} when is_binary(value) -> value
              value when is_binary(value) -> value
              _other -> nil
            end

          _ ->
            nil
        end
    end
  end

  defp text_like_file?(%Media{media_type: media_type, filename: filename}) do
    cond do
      is_binary(media_type) and String.starts_with?(media_type, "text/") ->
        true

      is_binary(media_type) and media_type in ["application/json", "application/xml"] ->
        true

      is_binary(filename) and Path.extname(filename) in [".txt", ".md", ".json", ".csv", ".xml"] ->
        true

      true ->
        false
    end
  end

  defp role_for(%Message{metadata: metadata, author: author}) do
    role = metadata[:role] || metadata["role"]

    cond do
      role in [:system, "system"] -> "system"
      role in [:assistant, "assistant"] -> "assistant"
      role in [:user, "user"] -> "user"
      author && author.is_me -> "assistant"
      true -> "user"
    end
  end

  defp maybe_put_name(message, %Message{author: author}, opts) do
    if opts[:include_names] && author do
      Map.put(message, :name, author.user_name || author.full_name)
    else
      message
    end
  end

  defp transform_message(ai_message, message, opts) do
    case opts[:transform] do
      callback when is_function(callback, 2) -> callback.(ai_message, message)
      callback when is_function(callback, 1) -> callback.(ai_message)
      _ -> ai_message
    end
  end

  defp text_only_parts?(parts), do: Enum.all?(parts, &match?(%{type: "text"}, &1))
  defp single_text([]), do: ""
  defp single_text([%{text: text}]), do: text
  defp single_text(parts), do: Enum.map_join(parts, "\n", &Map.get(&1, :text, ""))
end
