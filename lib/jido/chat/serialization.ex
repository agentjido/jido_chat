defmodule Jido.Chat.Serialization do
  @moduledoc false

  alias Jido.Chat.{
    Card,
    CapabilityMatrix,
    ChannelRef,
    EventEnvelope,
    FileUpload,
    IngressResult,
    Markdown,
    Message,
    Modal,
    ModalResult,
    ModalResponse,
    PostPayload,
    SentMessage,
    StreamChunk,
    Thread,
    WebhookRequest,
    WebhookResponse,
    Wire
  }

  @spec to_map(map()) :: map()
  def to_map(chat) when is_map(chat) do
    %{
      id: chat.id,
      user_name: chat.user_name,
      adapters: serialize_adapters(chat.adapters),
      state_adapter: Wire.encode_module(chat.state_adapter),
      subscriptions: chat.subscriptions |> MapSet.to_list() |> Enum.sort(),
      dedupe: serialize_dedupe(chat.dedupe),
      dedupe_order: serialize_dedupe_order(chat.dedupe_order || []),
      handlers: serialize_handlers(chat.handlers),
      metadata: Wire.to_plain(chat.metadata),
      thread_state: Wire.to_plain(chat.thread_state),
      channel_state: Wire.to_plain(chat.channel_state),
      initialized: chat.initialized
    }
    |> Wire.to_plain()
    |> Map.put("__type__", "chat")
  end

  @spec from_map(map()) :: map()
  def from_map(map) when is_map(map) do
    chat =
      Jido.Chat.new(%{
        id: map[:id] || map["id"],
        user_name: map[:user_name] || map["user_name"],
        adapters: deserialize_adapters(map[:adapters] || map["adapters"] || %{}),
        state_adapter: map[:state_adapter] || map["state_adapter"],
        metadata: map[:metadata] || map["metadata"] || %{},
        subscriptions: map[:subscriptions] || map["subscriptions"] || [],
        dedupe: map[:dedupe] || map["dedupe"] || [],
        dedupe_order: map[:dedupe_order] || map["dedupe_order"] || [],
        thread_state: map[:thread_state] || map["thread_state"] || %{},
        channel_state: map[:channel_state] || map["channel_state"] || %{}
      })

    %{
      chat
      | initialized: map[:initialized] || map["initialized"] || false,
        handlers: deserialize_handlers(map[:handlers] || map["handlers"] || %{}, chat.handlers)
    }
  end

  @spec reviver() :: (map() -> term())
  def reviver, do: &revive/1

  @spec revive(map()) :: term()
  def revive(%{"__type__" => "chat"} = map), do: from_map(map)
  def revive(%{"__type__" => "thread"} = map), do: Thread.from_map(map)
  def revive(%{"__type__" => "channel"} = map), do: ChannelRef.from_map(map)
  def revive(%{"__type__" => "markdown"} = map), do: Markdown.from_map(map)
  def revive(%{"__type__" => "markdown_node"} = map), do: Jido.Chat.Markdown.Node.from_map(map)
  def revive(%{"__type__" => "card"} = map), do: Card.from_map(map)
  def revive(%{"__type__" => "card_component"} = map), do: Jido.Chat.Card.Component.from_map(map)
  def revive(%{"__type__" => "modal"} = map), do: Modal.from_map(map)
  def revive(%{"__type__" => "modal_element"} = map), do: Jido.Chat.Modal.Element.from_map(map)
  def revive(%{"__type__" => "message"} = map), do: Message.from_map(map)
  def revive(%{"__type__" => "file_upload"} = map), do: FileUpload.from_map(map)
  def revive(%{"__type__" => "post_payload"} = map), do: PostPayload.from_map(map)
  def revive(%{"__type__" => "sent_message"} = map), do: SentMessage.from_map(map)
  def revive(%{"__type__" => "stream_chunk"} = map), do: StreamChunk.from_map(map)
  def revive(%{"__type__" => "event_envelope"} = map), do: EventEnvelope.from_map(map)
  def revive(%{"__type__" => "ingress_result"} = map), do: IngressResult.from_map(map)
  def revive(%{"__type__" => "modal_result"} = map), do: ModalResult.from_map(map)
  def revive(%{"__type__" => "modal_response"} = map), do: ModalResponse.from_map(map)
  def revive(%{"__type__" => "capability_matrix"} = map), do: CapabilityMatrix.from_map(map)
  def revive(%{"__type__" => "webhook_request"} = map), do: WebhookRequest.from_map(map)
  def revive(%{"__type__" => "webhook_response"} = map), do: WebhookResponse.from_map(map)
  def revive(map), do: map

  defp serialize_adapters(adapters) when is_map(adapters) do
    adapters
    |> Enum.map(fn {name, module} -> {to_string(name), Wire.encode_module(module)} end)
    |> Map.new()
  end

  defp serialize_dedupe(%MapSet{} = dedupe) do
    dedupe
    |> Enum.map(fn {adapter_name, message_id} ->
      [to_string(adapter_name), to_string(message_id)]
    end)
    |> Enum.sort()
  end

  defp serialize_handlers(handlers) when is_map(handlers) do
    counts =
      handlers
      |> Enum.map(fn {key, value} ->
        {to_string(key), if(is_list(value), do: length(value), else: 0)}
      end)
      |> Map.new()

    %{"serializable" => false, "counts" => counts}
  end

  defp deserialize_adapters(adapters) when is_map(adapters) do
    adapters
    |> Enum.map(fn {key, value} ->
      {normalize_key_atom(key), Wire.decode_module(value)}
    end)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp deserialize_adapters(_), do: %{}

  defp serialize_dedupe_order(dedupe_order) when is_list(dedupe_order) do
    dedupe_order
    |> Enum.map(fn
      {adapter_name, message_id} -> [to_string(adapter_name), to_string(message_id)]
      [adapter_name, message_id] -> [to_string(adapter_name), to_string(message_id)]
      _other -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp serialize_dedupe_order(_), do: []

  defp deserialize_handlers(handlers, defaults) when is_map(handlers) and is_map(defaults) do
    serializable? = handlers[:serializable] || handlers["serializable"] || false
    if serializable?, do: defaults, else: defaults
  end

  defp deserialize_handlers(_handlers, defaults), do: defaults

  defp normalize_key_atom(key) when is_atom(key), do: key

  defp normalize_key_atom(key) when is_binary(key) do
    String.to_atom(key)
  end

  defp normalize_key_atom(key), do: key
end
