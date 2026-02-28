defmodule Jido.Chat.ChannelRef do
  @moduledoc """
  Channel handle for adapter-routed posting, state, and metadata access.
  """

  alias Jido.Chat.{
    Adapter,
    ChannelInfo,
    MessagePage,
    ModalResult,
    PostPayload,
    Postable,
    SentMessage,
    ThreadPage,
    Wire
  }

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              adapter_name: Zoi.atom(),
              adapter: Zoi.any(),
              external_id: Zoi.any(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for ChannelRef."
  def schema, do: @schema

  @doc "Creates a channel reference."
  def new(attrs) when is_map(attrs), do: Jido.Chat.Schema.parse!(__MODULE__, @schema, attrs)

  @doc "Posts string/postable/stream content to channel via adapter."
  @spec post(t(), String.t() | Postable.t() | map() | Enumerable.t(), keyword()) ::
          {:ok, SentMessage.t()} | {:error, term()}
  def post(channel, input, opts \\ [])

  def post(%__MODULE__{} = channel, text, opts) when is_binary(text),
    do: text |> PostPayload.text() |> then(&post_payload(channel, &1, opts))

  def post(%__MODULE__{} = channel, %Postable{} = postable, opts),
    do: postable |> Postable.to_payload() |> then(&post_payload(channel, &1, opts))

  def post(%__MODULE__{} = channel, postable_map, opts) when is_map(postable_map) do
    postable_map
    |> Postable.new()
    |> Postable.to_payload()
    |> then(&post_payload(channel, &1, opts))
  rescue
    _ -> {:error, :invalid_postable}
  end

  def post(%__MODULE__{} = channel, enumerable, opts) do
    if Enumerable.impl_for(enumerable) do
      post_stream(channel, enumerable, opts)
    else
      {:error, :invalid_postable}
    end
  end

  @doc "Opens a modal in the channel when supported by the adapter."
  @spec open_modal(t(), map(), keyword()) :: {:ok, ModalResult.t()} | {:error, term()}
  def open_modal(%__MODULE__{} = channel, payload, opts \\ []) when is_map(payload) do
    Adapter.open_modal(channel.adapter, channel.external_id, payload, opts)
  end

  @doc "Posts an ephemeral message via adapter when supported."
  @spec post_ephemeral(t(), String.t() | integer(), String.t(), keyword()) ::
          {:ok, Jido.Chat.EphemeralMessage.t()} | {:error, term()}
  def post_ephemeral(%__MODULE__{} = channel, user_id, text, opts \\ []) when is_binary(text) do
    Adapter.post_ephemeral(channel.adapter, channel.external_id, user_id, text, opts)
  end

  @doc "Starts typing indicator on channel when supported."
  @spec start_typing(t(), String.t() | nil) :: :ok | {:error, term()}
  def start_typing(%__MODULE__{} = channel, status \\ nil) do
    opts = if is_binary(status), do: [status: status], else: []
    Adapter.start_typing(channel.adapter, channel.external_id, opts)
  end

  @doc "Renders adapter-specific mention format for a user id."
  @spec mention_user(t(), String.t() | integer()) :: String.t()
  def mention_user(%__MODULE__{adapter_name: :discord}, user_id), do: "<@#{user_id}>"
  def mention_user(%__MODULE__{adapter_name: :telegram}, user_id), do: "@#{user_id}"
  def mention_user(%__MODULE__{}, user_id), do: "@#{user_id}"

  @doc "Gets channel state map or a single key from chat struct state."
  @spec state(Jido.Chat.t(), t(), term() | nil) :: map() | term()
  def state(%Jido.Chat{} = chat, %__MODULE__{} = channel, key \\ nil) do
    channel_state = Jido.Chat.channel_state(chat, channel.id)
    if is_nil(key), do: channel_state, else: Map.get(channel_state, key)
  end

  @doc "Sets channel state in chat struct using :replace, :merge, or key/value modes."
  @spec set_state(Jido.Chat.t(), t(), atom() | term(), map() | term()) :: Jido.Chat.t()
  def set_state(%Jido.Chat{} = chat, %__MODULE__{} = channel, :replace, %{} = value) do
    Jido.Chat.put_channel_state(chat, channel.id, value)
  end

  def set_state(%Jido.Chat{} = chat, %__MODULE__{} = channel, :merge, %{} = value) do
    merged = Map.merge(Jido.Chat.channel_state(chat, channel.id), value)
    Jido.Chat.put_channel_state(chat, channel.id, merged)
  end

  def set_state(%Jido.Chat{} = chat, %__MODULE__{} = channel, key, value) do
    next_state = Map.put(Jido.Chat.channel_state(chat, channel.id), key, value)
    Jido.Chat.put_channel_state(chat, channel.id, next_state)
  end

  @doc "Returns cached channel name from metadata when present."
  @spec name(t()) :: String.t() | nil
  def name(%__MODULE__{} = channel) do
    channel.metadata[:name] || channel.metadata["name"] || channel.metadata[:title] ||
      channel.metadata["title"]
  end

  @doc "Fetches channel metadata as `Jido.Chat.ChannelInfo`."
  @spec fetch_metadata(t(), keyword()) :: {:ok, ChannelInfo.t()} | {:error, term()}
  def fetch_metadata(%__MODULE__{} = channel, opts \\ []) do
    Adapter.fetch_metadata(channel.adapter, channel.external_id, opts)
  end

  @doc "Fetches a page of channel-level messages when supported."
  @spec messages(t(), keyword() | map() | Jido.Chat.FetchOptions.t()) ::
          {:ok, MessagePage.t()} | {:error, term()}
  def messages(%__MODULE__{} = channel, opts \\ []) do
    opts = normalize_fetch_opts(opts)
    Adapter.fetch_channel_messages(channel.adapter, channel.external_id, opts)
  end

  @doc "Lists thread summaries in this channel when supported."
  @spec threads(t(), keyword()) :: {:ok, ThreadPage.t()} | {:error, term()}
  def threads(%__MODULE__{} = channel, opts \\ []) do
    Adapter.list_threads(channel.adapter, channel.external_id, opts)
  end

  @doc "Returns a lazy stream over channel messages using cursor pagination."
  @spec messages_stream(t(), keyword() | map() | Jido.Chat.FetchOptions.t()) :: Enumerable.t()
  def messages_stream(%__MODULE__{} = channel, opts \\ []) do
    base_opts = normalize_fetch_opts(opts)

    Stream.resource(
      fn -> %{channel: channel, opts: base_opts, cursor: nil, pending: [], done?: false} end,
      &next_message_batch/1,
      fn _state -> :ok end
    )
  end

  @doc "Returns a lazy stream over channel thread summaries using cursor pagination."
  @spec threads_stream(t(), keyword()) :: Enumerable.t()
  def threads_stream(%__MODULE__{} = channel, opts \\ []) do
    Stream.resource(
      fn -> %{channel: channel, opts: opts, cursor: nil, pending: [], done?: false} end,
      &next_thread_batch/1,
      fn _state -> :ok end
    )
  end

  @doc "Serializes channel ref into a plain map with type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = channel) do
    channel
    |> Map.from_struct()
    |> Map.update!(:adapter, &Wire.encode_module/1)
    |> Wire.to_plain()
    |> Map.put("__type__", "channel")
  end

  @doc "Builds a channel ref from serialized map data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    adapter = map[:adapter] || map["adapter"]

    map
    |> Map.drop(["__type__", :__type__])
    |> Map.delete("adapter")
    |> Map.put(:adapter, Wire.decode_module(adapter))
    |> new()
  end

  defp post_payload(%__MODULE__{} = channel, %PostPayload{} = payload, opts) do
    with {:ok, response} <-
           Adapter.post_channel_message(
             channel.adapter,
             channel.external_id,
             payload.text || "",
             opts
           ) do
      {:ok,
       SentMessage.new(%{
         id: response.external_message_id || Jido.Chat.ID.generate!(),
         thread_id: channel.id,
         adapter: channel.adapter,
         external_room_id: channel.external_id,
         text: payload.text,
         formatted: payload.formatted || payload.text,
         raw: payload.raw,
         attachments: payload.attachments,
         metadata: payload.metadata,
         response: response,
         default_opts: opts
       })}
    end
  end

  defp post_stream(%__MODULE__{} = channel, enumerable, opts) do
    with {:ok, response} <-
           Adapter.stream(channel.adapter, channel.external_id, enumerable, opts) do
      {:ok,
       SentMessage.new(%{
         id: response.external_message_id || Jido.Chat.ID.generate!(),
         thread_id: channel.id,
         adapter: channel.adapter,
         external_room_id: channel.external_id,
         raw: response.raw,
         metadata: %{stream: true},
         response: response,
         default_opts: opts
       })}
    end
  end

  defp normalize_fetch_opts(%Jido.Chat.FetchOptions{} = opts),
    do: Jido.Chat.FetchOptions.to_keyword(opts)

  defp normalize_fetch_opts(opts) when is_map(opts),
    do: opts |> Jido.Chat.FetchOptions.new() |> Jido.Chat.FetchOptions.to_keyword()

  defp normalize_fetch_opts(opts) when is_list(opts),
    do: opts |> Jido.Chat.FetchOptions.new() |> Jido.Chat.FetchOptions.to_keyword()

  defp normalize_fetch_opts(_other),
    do: Jido.Chat.FetchOptions.to_keyword(Jido.Chat.FetchOptions.new(%{}))

  defp next_message_batch(%{pending: [next | rest]} = state),
    do: {[next], %{state | pending: rest}}

  defp next_message_batch(%{done?: true} = state), do: {:halt, state}

  defp next_message_batch(%{channel: channel, opts: opts, cursor: cursor} = state) do
    request_opts =
      case cursor do
        nil -> opts
        next_cursor -> Keyword.put(opts, :cursor, next_cursor)
      end

    case messages(channel, request_opts) do
      {:ok, %MessagePage{} = page} ->
        pending = page.messages || []
        done? = is_nil(page.next_cursor)
        next_cursor = page.next_cursor

        case pending do
          [] ->
            if is_nil(next_cursor) do
              {:halt, %{state | done?: true}}
            else
              next_message_batch(%{state | pending: [], cursor: next_cursor, done?: done?})
            end

          [first | rest] ->
            {[first], %{state | pending: rest, cursor: next_cursor, done?: done?}}
        end

      {:error, _reason} ->
        {:halt, %{state | done?: true}}
    end
  end

  defp next_thread_batch(%{pending: [next | rest]} = state),
    do: {[next], %{state | pending: rest}}

  defp next_thread_batch(%{done?: true} = state), do: {:halt, state}

  defp next_thread_batch(%{channel: channel, opts: opts, cursor: cursor} = state) do
    request_opts =
      case cursor do
        nil -> opts
        next_cursor -> Keyword.put(opts, :cursor, next_cursor)
      end

    case threads(channel, request_opts) do
      {:ok, %ThreadPage{} = page} ->
        pending = page.threads || []
        done? = is_nil(page.next_cursor)
        next_cursor = page.next_cursor

        case pending do
          [] ->
            if is_nil(next_cursor) do
              {:halt, %{state | done?: true}}
            else
              next_thread_batch(%{state | pending: [], cursor: next_cursor, done?: done?})
            end

          [first | rest] ->
            {[first], %{state | pending: rest, cursor: next_cursor, done?: done?}}
        end

      {:error, _reason} ->
        {:halt, %{state | done?: true}}
    end
  end
end
