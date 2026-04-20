defmodule Jido.Chat.Capabilities do
  @moduledoc """
  Capabilities negotiation for adapters and participants.

  Provides functions to check and filter inbound content blocks and outbound
  post payloads based on channel capabilities.
  """

  alias Jido.Chat.{Adapter, Attachment, FileUpload, PostPayload, Postable}
  alias Jido.Chat.Content.{Audio, File, Image, Text, ToolResult, ToolUse, Video}

  @type capability ::
          :text
          | :image
          | :audio
          | :video
          | :file
          | :multi_file
          | :markdown
          | :cards
          | :modals
          | :ephemeral
          | :tool_use
          | :streaming
          | :reactions
          | :threads
          | :typing
          | :presence
          | :read_receipts
          | :assistant_events

  @type capabilities :: [capability()]

  @all_capabilities [
    :text,
    :image,
    :audio,
    :video,
    :file,
    :multi_file,
    :markdown,
    :cards,
    :modals,
    :ephemeral,
    :tool_use,
    :streaming,
    :reactions,
    :threads,
    :typing,
    :presence,
    :read_receipts,
    :assistant_events
  ]

  @doc "Returns all supported capability atoms."
  @spec all() :: capabilities()
  def all, do: @all_capabilities

  @doc "Checks if a capability is in the list of capabilities."
  @spec supports?(capabilities(), capability()) :: boolean()
  def supports?(capabilities, capability) when is_list(capabilities) and is_atom(capability) do
    capability in capabilities
  end

  @doc "Returns the list of capabilities required for an inbound content block."
  @spec content_requires(struct()) :: capabilities()
  def content_requires(%Text{}), do: [:text]
  def content_requires(%Image{}), do: [:image]
  def content_requires(%Audio{}), do: [:audio]
  def content_requires(%Video{}), do: [:video]
  def content_requires(%File{}), do: [:file]
  def content_requires(%ToolUse{}), do: [:tool_use]
  def content_requires(%ToolResult{}), do: [:text]
  def content_requires(_), do: [:text]

  @doc "Checks if a channel can deliver the given outbound postable payload."
  @spec can_deliver?(capabilities(), Postable.t() | PostPayload.t() | map()) :: boolean()
  def can_deliver?(channel_caps, %Postable{} = postable) when is_list(channel_caps) do
    can_deliver?(channel_caps, Postable.to_payload(postable))
  end

  def can_deliver?(channel_caps, %PostPayload{} = payload) when is_list(channel_caps) do
    uploads_supported? =
      payload
      |> upload_requires()
      |> Enum.all?(&supports?(channel_caps, &1))

    content_supported? =
      case payload.kind do
        :stream ->
          supports?(channel_caps, :streaming)

        :card ->
          supports?(channel_caps, :cards) or
            (supports?(channel_caps, :text) and is_binary(payload.fallback_text || payload.text))

        :markdown ->
          supports?(channel_caps, :markdown) or supports?(channel_caps, :text)

        _other ->
          supports?(channel_caps, :text)
      end

    uploads_supported? and content_supported?
  end

  def can_deliver?(channel_caps, payload)
      when is_list(channel_caps) and is_map(payload) and not is_struct(payload) do
    try do
      payload
      |> PostPayload.new()
      |> then(&can_deliver?(channel_caps, &1))
    rescue
      _ -> false
    end
  end

  @spec can_deliver?(capabilities(), struct()) :: boolean()
  def can_deliver?(channel_caps, content) when is_list(channel_caps) do
    required = content_requires(content)
    Enum.all?(required, &supports?(channel_caps, &1))
  end

  @doc "Filters a list of content or outbound payloads to only what the channel supports."
  @spec filter_content([term()], capabilities()) :: [term()]
  def filter_content(content_list, channel_caps)
      when is_list(content_list) and is_list(channel_caps) do
    Enum.filter(content_list, &can_deliver?(channel_caps, &1))
  end

  @doc "Returns a list of content or outbound payloads that the channel cannot deliver."
  @spec unsupported_content([term()], capabilities()) :: [term()]
  def unsupported_content(content_list, channel_caps)
      when is_list(content_list) and is_list(channel_caps) do
    Enum.reject(content_list, &can_deliver?(channel_caps, &1))
  end

  @doc "Returns the delivery-focused capability list for an adapter module."
  @spec channel_capabilities(module()) :: capabilities()
  def channel_capabilities(adapter_module) when is_atom(adapter_module) do
    capabilities =
      if Code.ensure_loaded?(adapter_module) and
           function_exported?(adapter_module, :capabilities, 0) do
        case adapter_module.capabilities() do
          caps when is_list(caps) -> caps
          _ -> Adapter.capabilities(adapter_module)
        end
      else
        Adapter.capabilities(adapter_module)
      end

    normalize_adapter_capabilities(capabilities)
  end

  defp normalize_adapter_capabilities(capabilities) when is_list(capabilities) do
    capabilities
    |> Enum.filter(&(&1 in @all_capabilities))
    |> case do
      [] -> [:text]
      filtered -> filtered
    end
  end

  defp normalize_adapter_capabilities(capabilities) when is_map(capabilities) do
    media_supported? =
      supported_status?(capabilities[:image]) or
        supported_status?(capabilities[:audio]) or
        supported_status?(capabilities[:video]) or
        supported_status?(capabilities[:file]) or
        supported_status?(capabilities[:send_file]) or
        supported_status?(capabilities[:post_message])

    multi_file_supported? =
      supported_status?(capabilities[:multi_file]) or
        supported_status?(capabilities[:post_message])

    [:text]
    |> maybe_add_capability(:image, media_supported?)
    |> maybe_add_capability(:audio, media_supported?)
    |> maybe_add_capability(:video, media_supported?)
    |> maybe_add_capability(:file, media_supported?)
    |> maybe_add_capability(:multi_file, multi_file_supported?)
    |> maybe_add_capability(:markdown, supported_status?(capabilities[:markdown]))
    |> maybe_add_capability(:cards, supported_status?(capabilities[:cards]))
    |> maybe_add_capability(
      :modals,
      supported_status?(capabilities[:modals]) or supported_status?(capabilities[:open_modal])
    )
    |> maybe_add_capability(
      :ephemeral,
      supported_status?(capabilities[:ephemeral]) or
        supported_status?(capabilities[:post_ephemeral])
    )
    |> maybe_add_capability(
      :threads,
      supported_status?(capabilities[:open_thread]) or
        supported_status?(capabilities[:list_threads])
    )
    |> maybe_add_capability(
      :reactions,
      supported_status?(capabilities[:add_reaction]) or
        supported_status?(capabilities[:remove_reaction])
    )
    |> maybe_add_capability(:typing, supported_status?(capabilities[:start_typing]))
    |> maybe_add_capability(:streaming, supported_status?(capabilities[:stream]))
    |> maybe_add_capability(:assistant_events, supported_status?(capabilities[:assistant_events]))
  end

  defp normalize_adapter_capabilities(_), do: [:text]

  defp upload_requires(%PostPayload{} = payload) do
    uploads = PostPayload.upload_candidates(payload)

    uploads
    |> Enum.flat_map(&upload_requires/1)
    |> maybe_require_multi_file(length(uploads))
  end

  defp upload_requires(%Attachment{kind: kind}), do: upload_requires(kind)
  defp upload_requires(%FileUpload{kind: kind}), do: upload_requires(kind)
  defp upload_requires(:image), do: [:image]
  defp upload_requires(:audio), do: [:audio]
  defp upload_requires(:video), do: [:video]
  defp upload_requires(_kind), do: [:file]

  defp maybe_require_multi_file(capabilities, count) when count > 1,
    do: Enum.uniq([:multi_file | capabilities])

  defp maybe_require_multi_file(capabilities, _count), do: Enum.uniq(capabilities)

  defp supported_status?(status), do: status in [:native, :fallback]

  defp maybe_add_capability(capabilities, _capability, false), do: capabilities

  defp maybe_add_capability(capabilities, capability, true) do
    Enum.uniq(capabilities ++ [capability])
  end
end
