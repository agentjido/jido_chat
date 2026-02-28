defmodule Jido.Chat.Capabilities do
  @moduledoc """
  Capabilities negotiation for channels and participants.

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
  - `:listener_lifecycle` - Listener child-spec lifecycle hook
  - `:routing_metadata` - Routing metadata extraction hook
  - `:sender_verification` - Sender verification hook
  - `:outbound_sanitization` - Outbound sanitization hook
  - `:media_send` - Outbound media send hook
  - `:media_edit` - Outbound media edit hook
  - `:command_hints` - Command hint extraction hook
  - `:message_edit` - Text message edit hook

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
          | :listener_lifecycle
          | :routing_metadata
          | :sender_verification
          | :outbound_sanitization
          | :media_send
          | :media_edit
          | :command_hints
          | :message_edit

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
    :read_receipts,
    :listener_lifecycle,
    :routing_metadata,
    :sender_verification,
    :outbound_sanitization,
    :media_send,
    :media_edit,
    :command_hints,
    :message_edit
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
  Returns the capabilities for a channel module.

  If the channel implements the `capabilities/0` callback, returns those capabilities.
  Otherwise returns the default `[:text]`.

  ## Examples

      iex> Capabilities.channel_capabilities(Jido.Chat.Channels.Discord)
      [:text, :image, :audio, :video, :file, :reactions, :threads]
  """
  @spec channel_capabilities(module()) :: capabilities()
  def channel_capabilities(channel_module) when is_atom(channel_module) do
    Jido.Chat.Channel.capabilities(channel_module)
  end
end
