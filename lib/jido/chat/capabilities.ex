defmodule Jido.Chat.Capabilities do
  @moduledoc """
  Capabilities negotiation for adapters and participants.

  Provides functions to check and filter content based on channel capabilities,
  preventing content type mismatches between channels and participants.

  ## Supported Capabilities

  - `:text` - Plain text messages
  - `:image` - Image attachments
  - `:audio` - Audio files and voice messages
  - `:video` - Video attachments
  - `:file` - Generic file attachments
  - `:tool_use` - Tool/action invocation blocks
  - `:streaming` - Incremental message updates
  - `:reactions` - Message reactions
  - `:threads` - Threaded conversations
  - `:typing` - Typing indicators
  - `:presence` - Presence status updates
  - `:read_receipts` - Delivery and read receipts

  ## Examples

      # Check if a channel can deliver content
      iex> Capabilities.can_deliver?([:text, :image], %Content.Image{url: "..."})
      true

      iex> Capabilities.can_deliver?([:text], %Content.Image{url: "..."})
      false

      # Filter content to what a channel supports
      iex> content = [%Content.Text{text: "Hi"}, %Content.Image{url: "..."}]
      iex> Capabilities.filter_content(content, [:text])
      [%Content.Text{text: "Hi"}]
  """

  alias Jido.Chat.Content.{Text, Image, Audio, Video, File, ToolUse, ToolResult}

  @type capability ::
          :text
          | :image
          | :audio
          | :video
          | :file
          | :tool_use
          | :streaming
          | :reactions
          | :threads
          | :typing
          | :presence
          | :read_receipts

  @type capabilities :: [capability()]

  @all_capabilities [
    :text,
    :image,
    :audio,
    :video,
    :file,
    :tool_use,
    :streaming,
    :reactions,
    :threads,
    :typing,
    :presence,
    :read_receipts
  ]

  @doc """
  Returns all supported capability atoms.
  """
  @spec all :: capabilities()
  def all, do: @all_capabilities

  @doc """
  Checks if a capability is in the list of capabilities.

  ## Examples

      iex> Capabilities.supports?([:text, :image], :text)
      true

      iex> Capabilities.supports?([:text], :image)
      false
  """
  @spec supports?(capabilities(), capability()) :: boolean()
  def supports?(capabilities, capability) when is_list(capabilities) and is_atom(capability) do
    capability in capabilities
  end

  @doc """
  Returns the list of capabilities required for a content type.

  ## Examples

      iex> Capabilities.content_requires(%Content.Text{text: "hello"})
      [:text]

      iex> Capabilities.content_requires(%Content.Image{url: "..."})
      [:image]
  """
  @spec content_requires(struct()) :: capabilities()
  def content_requires(%Text{}), do: [:text]
  def content_requires(%Image{}), do: [:image]
  def content_requires(%Audio{}), do: [:audio]
  def content_requires(%Video{}), do: [:video]
  def content_requires(%File{}), do: [:file]
  def content_requires(%ToolUse{}), do: [:tool_use]
  def content_requires(%ToolResult{}), do: [:text]
  def content_requires(_), do: [:text]

  @doc """
  Checks if a channel can deliver the given content.

  Returns true if the channel capabilities include all requirements for the content.

  ## Examples

      iex> Capabilities.can_deliver?([:text, :image], %Content.Text{text: "hello"})
      true

      iex> Capabilities.can_deliver?([:text], %Content.Image{url: "..."})
      false
  """
  @spec can_deliver?(capabilities(), struct()) :: boolean()
  def can_deliver?(channel_caps, content) when is_list(channel_caps) do
    required = content_requires(content)
    Enum.all?(required, &supports?(channel_caps, &1))
  end

  @doc """
  Filters a list of content to only what the channel supports.

  Returns a list containing only content that the channel can deliver.

  ## Examples

      iex> content = [%Content.Text{text: "Hi"}, %Content.Image{url: "..."}]
      iex> Capabilities.filter_content(content, [:text])
      [%Content.Text{text: "Hi"}]
  """
  @spec filter_content([struct()], capabilities()) :: [struct()]
  def filter_content(content_list, channel_caps)
      when is_list(content_list) and is_list(channel_caps) do
    Enum.filter(content_list, &can_deliver?(channel_caps, &1))
  end

  @doc """
  Returns a list of content that the channel cannot deliver.

  ## Examples

      iex> content = [%Content.Text{text: "Hi"}, %Content.Image{url: "..."}]
      iex> Capabilities.unsupported_content(content, [:text])
      [%Content.Image{url: "..."}]
  """
  @spec unsupported_content([struct()], capabilities()) :: [struct()]
  def unsupported_content(content_list, channel_caps)
      when is_list(content_list) and is_list(channel_caps) do
    Enum.reject(content_list, &can_deliver?(channel_caps, &1))
  end

  @doc """
  Returns the content capabilities for an adapter module.

  Legacy channel wrappers have been removed. This helper now accepts the canonical
  `Jido.Chat.Adapter` module and derives a content-focused capability list from the
  adapter surface. When an adapter only exposes the operational capability matrix,
  the content fallback remains `[:text]`.

  ## Examples

      iex> Capabilities.channel_capabilities(Jido.Chat.Discord.Adapter)
      [:text, :reactions, :threads]
  """
  @spec channel_capabilities(module()) :: capabilities()
  def channel_capabilities(adapter_module) when is_atom(adapter_module) do
    cond do
      function_exported?(adapter_module, :capabilities, 0) ->
        normalize_adapter_capabilities(adapter_module.capabilities())

      true ->
        [:text]
    end
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
      supported_status?(capabilities[:post_message]) or
        supported_status?(capabilities[:send_file])

    [:text]
    |> maybe_add_capability(:image, media_supported?)
    |> maybe_add_capability(:audio, media_supported?)
    |> maybe_add_capability(:video, media_supported?)
    |> maybe_add_capability(:file, media_supported?)
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
  end

  defp normalize_adapter_capabilities(_), do: [:text]

  defp supported_status?(status), do: status in [:native, :fallback]

  defp maybe_add_capability(capabilities, _capability, false), do: capabilities

  defp maybe_add_capability(capabilities, capability, true) do
    Enum.uniq(capabilities ++ [capability])
  end
end
