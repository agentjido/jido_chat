defmodule Jido.Chat.Thread do
  @moduledoc """
  Thread handle with posting, lifecycle, state, and discovery helpers.
  """

  alias Jido.Chat.{
    Adapter,
    Author,
    ChannelRef,
    Message,
    MessagePage,
    ModalResult,
    PostPayload,
    Postable,
    SentMessage,
    Wire
  }

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              adapter_name: Zoi.atom(),
              adapter: Zoi.any(),
              external_room_id: Zoi.any(),
              external_thread_id: Zoi.string() |> Zoi.nullish(),
              channel_id: Zoi.string() |> Zoi.nullish(),
              is_dm: Zoi.boolean() |> Zoi.default(false),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Thread."
  def schema, do: @schema

  @doc "Creates a thread handle."
  def new(attrs) when is_map(attrs) do
    attrs
    |> Map.put_new(
      :channel_id,
      "#{attrs[:adapter_name] || attrs["adapter_name"]}:#{attrs[:external_room_id] || attrs["external_room_id"]}"
    )
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Posts string/postable/stream content and returns a sent-message handle."
  @spec post(t(), String.t() | Postable.t() | map() | Enumerable.t(), keyword()) ::
          {:ok, SentMessage.t()} | {:error, term()}
  def post(thread, input, opts \\ [])

  def post(%__MODULE__{} = thread, text, opts) when is_binary(text) do
    text
    |> PostPayload.text()
    |> then(&post_payload(thread, &1, opts))
  end

  def post(%__MODULE__{} = thread, %Postable{} = postable, opts) do
    postable
    |> Postable.to_payload()
    |> then(&post_payload(thread, &1, opts))
  end

  def post(%__MODULE__{} = thread, postable_map, opts) when is_map(postable_map) do
    postable_map
    |> Postable.new()
    |> Postable.to_payload()
    |> then(&post_payload(thread, &1, opts))
  rescue
    _ -> {:error, :invalid_postable}
  end

  def post(%__MODULE__{} = thread, enumerable, opts) do
    if Enumerable.impl_for(enumerable) do
      post_stream(thread, enumerable, opts)
    else
      {:error, :invalid_postable}
    end
  end

  @doc "Opens a modal in the thread when supported by the adapter."
  @spec open_modal(t(), map(), keyword()) :: {:ok, ModalResult.t()} | {:error, term()}
  def open_modal(%__MODULE__{} = thread, payload, opts \\ []) when is_map(payload) do
    opts = with_thread_opts(thread, opts)
    Adapter.open_modal(thread.adapter, thread.external_room_id, payload, opts)
  end

  @doc "Edits a previously-sent message via adapter `edit_message/4` when supported."
  @spec edit(t(), String.t() | integer(), String.t(), keyword()) :: Adapter.send_result()
  def edit(%__MODULE__{} = thread, message_id, text, opts \\ []) do
    Adapter.edit_message(
      thread.adapter,
      thread.external_room_id,
      message_id,
      text,
      with_thread_opts(thread, opts)
    )
  end

  @doc "Returns a channel reference tied to this thread's room."
  @spec channel(Jido.Chat.t(), t()) :: ChannelRef.t()
  def channel(%Jido.Chat{} = chat, %__MODULE__{} = thread) do
    Jido.Chat.channel(chat, thread.adapter_name, thread.external_room_id)
  end

  @doc "Returns the logical channel id for this thread."
  @spec channel_id(t()) :: String.t()
  def channel_id(%__MODULE__{} = thread),
    do: thread.channel_id || "#{thread.adapter_name}:#{thread.external_room_id}"

  @doc "Gets thread state map or a single key from chat struct state."
  @spec state(Jido.Chat.t(), t(), term() | nil) :: map() | term()
  def state(%Jido.Chat{} = chat, %__MODULE__{} = thread, key \\ nil) do
    thread_state = Jido.Chat.thread_state(chat, thread.id)
    if is_nil(key), do: thread_state, else: Map.get(thread_state, key)
  end

  @doc "Sets thread state in chat struct using :replace, :merge, or key/value modes."
  @spec set_state(Jido.Chat.t(), t(), atom() | term(), map() | term()) :: Jido.Chat.t()
  def set_state(%Jido.Chat{} = chat, %__MODULE__{} = thread, :replace, %{} = value) do
    Jido.Chat.put_thread_state(chat, thread.id, value)
  end

  def set_state(%Jido.Chat{} = chat, %__MODULE__{} = thread, :merge, %{} = value) do
    merged = Map.merge(Jido.Chat.thread_state(chat, thread.id), value)
    Jido.Chat.put_thread_state(chat, thread.id, merged)
  end

  def set_state(%Jido.Chat{} = chat, %__MODULE__{} = thread, key, value) do
    next_state = Map.put(Jido.Chat.thread_state(chat, thread.id), key, value)
    Jido.Chat.put_thread_state(chat, thread.id, next_state)
  end

  @doc "Starts a typing indicator in the thread when supported."
  @spec start_typing(t(), String.t() | nil) :: :ok | {:error, term()}
  def start_typing(%__MODULE__{} = thread, status \\ nil) do
    opts =
      thread
      |> with_thread_opts([])
      |> maybe_put_status(status)

    Adapter.start_typing(thread.adapter, thread.external_room_id, opts)
  end

  @doc "Posts an ephemeral message to a user with optional DM fallback policy."
  @spec post_ephemeral(t(), String.t() | integer() | Author.t() | map(), String.t(), keyword()) ::
          {:ok, Jido.Chat.EphemeralMessage.t()} | {:error, term()}
  def post_ephemeral(%__MODULE__{} = thread, user, text, opts \\ []) when is_binary(text) do
    with {:ok, external_user_id} <- external_user_id(user) do
      opts = with_thread_opts(thread, opts)

      Adapter.post_ephemeral(
        thread.adapter,
        thread.external_room_id,
        external_user_id,
        text,
        opts
      )
    end
  end

  @doc "Fetches a page of normalized messages for the thread when supported."
  @spec messages(t(), keyword() | map() | Jido.Chat.FetchOptions.t()) ::
          {:ok, MessagePage.t()} | {:error, term()}
  def messages(%__MODULE__{} = thread, opts \\ []) do
    opts =
      opts
      |> normalize_fetch_opts()
      |> with_thread_opts(thread)

    Adapter.fetch_messages(thread.adapter, thread.external_room_id, opts)
  end

  @doc "Fetches all available messages by following pagination cursors when supported."
  @spec all_messages(t(), keyword() | map() | Jido.Chat.FetchOptions.t()) ::
          {:ok, [Message.t()]} | {:error, term()}
  def all_messages(%__MODULE__{} = thread, opts \\ []) do
    base_opts = normalize_fetch_opts(opts)

    with {:ok, %MessagePage{} = page} <- messages(thread, base_opts) do
      collect_all_messages(thread, base_opts, page, page.messages, MapSet.new())
    end
  end

  @doc "Fetches a recent message list with default limit `20`."
  @spec recent_messages(t(), keyword()) :: {:ok, [Message.t()]} | {:error, term()}
  def recent_messages(%__MODULE__{} = thread, opts \\ []) do
    opts = Keyword.put_new(opts, :limit, 20)

    with {:ok, %MessagePage{} = page} <- messages(thread, opts) do
      {:ok, page.messages}
    end
  end

  @doc "Returns a lazy stream over thread messages using cursor pagination."
  @spec messages_stream(t(), keyword() | map() | Jido.Chat.FetchOptions.t()) :: Enumerable.t()
  def messages_stream(%__MODULE__{} = thread, opts \\ []) do
    base_opts = normalize_fetch_opts(opts)

    Stream.resource(
      fn -> %{thread: thread, opts: base_opts, cursor: nil, pending: [], done?: false} end,
      &next_message_batch/1,
      fn _state -> :ok end
    )
  end

  @doc "Alias for `messages_stream/2` to mirror full-history stream naming."
  @spec all_messages_stream(t(), keyword() | map() | Jido.Chat.FetchOptions.t()) :: Enumerable.t()
  def all_messages_stream(%__MODULE__{} = thread, opts \\ []), do: messages_stream(thread, opts)

  @doc "Refreshes thread metadata when adapter supports fetch_thread callback."
  @spec refresh(t(), keyword()) :: {:ok, t()} | {:error, term()}
  def refresh(%__MODULE__{} = thread, opts \\ []) do
    with {:ok, fetched} <- Adapter.fetch_thread(thread.adapter, thread.external_room_id, opts) do
      case fetched do
        %__MODULE__{} = fetched_thread ->
          {:ok, fetched_thread}

        map when is_map(map) ->
          {:ok,
           %{
             thread
             | metadata:
                 Map.merge(thread.metadata || %{}, map[:metadata] || map["metadata"] || %{}),
               external_thread_id:
                 map[:external_thread_id] || map["external_thread_id"] ||
                   thread.external_thread_id
           }}

        _ ->
          {:error, :invalid_thread}
      end
    end
  end

  @doc "Renders a user mention string for this thread's adapter."
  @spec mention_user(t(), String.t() | integer() | Author.t() | map()) :: String.t()
  def mention_user(%__MODULE__{} = thread, user) do
    user_id = mention_user_id(user)

    case thread.adapter_name do
      :discord -> "<@#{user_id}>"
      :telegram -> "@#{user_id}"
      _ -> "@#{user_id}"
    end
  end

  @doc "Subscribes this thread in a pure `Jido.Chat` state struct."
  @spec subscribe(Jido.Chat.t(), t()) :: Jido.Chat.t()
  def subscribe(%Jido.Chat{} = chat, %__MODULE__{} = thread) do
    %{chat | subscriptions: MapSet.put(chat.subscriptions, thread.id)}
  end

  @doc "Unsubscribes this thread in a pure `Jido.Chat` state struct."
  @spec unsubscribe(Jido.Chat.t(), t()) :: Jido.Chat.t()
  def unsubscribe(%Jido.Chat{} = chat, %__MODULE__{} = thread) do
    %{chat | subscriptions: MapSet.delete(chat.subscriptions, thread.id)}
  end

  @doc "Returns true when the thread is subscribed in a pure `Jido.Chat` state struct."
  @spec subscribed?(Jido.Chat.t(), t()) :: boolean()
  def subscribed?(%Jido.Chat{} = chat, %__MODULE__{} = thread) do
    MapSet.member?(chat.subscriptions, thread.id)
  end

  @doc "Serializes thread into a plain map with type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = thread) do
    thread
    |> Map.from_struct()
    |> Map.update!(:adapter, &Wire.encode_module/1)
    |> Wire.to_plain()
    |> Map.put("__type__", "thread")
  end

  @doc "Builds a thread from serialized map data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    adapter = map[:adapter] || map["adapter"]

    map
    |> Map.drop(["__type__", :__type__])
    |> Map.delete("adapter")
    |> Map.put(:adapter, Wire.decode_module(adapter))
    |> new()
  end

  defp post_payload(%__MODULE__{} = thread, %PostPayload{} = payload, opts) do
    opts = with_thread_opts(thread, opts)

    with {:ok, response} <-
           Adapter.send_message(
             thread.adapter,
             thread.external_room_id,
             payload.text || "",
             opts
           ) do
      {:ok,
       SentMessage.new(%{
         id: response.external_message_id || Jido.Chat.ID.generate!(),
         thread_id: thread.id,
         adapter: thread.adapter,
         external_room_id: thread.external_room_id,
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

  defp post_stream(%__MODULE__{} = thread, enumerable, opts) do
    opts = with_thread_opts(thread, opts)

    with {:ok, response} <-
           Adapter.stream(thread.adapter, thread.external_room_id, enumerable, opts) do
      {:ok,
       SentMessage.new(%{
         id: response.external_message_id || Jido.Chat.ID.generate!(),
         thread_id: thread.id,
         adapter: thread.adapter,
         external_room_id: thread.external_room_id,
         raw: response.raw,
         metadata: %{stream: true},
         response: response,
         default_opts: opts
       })}
    end
  end

  defp collect_all_messages(_thread, _base_opts, %MessagePage{next_cursor: nil}, acc, _seen),
    do: {:ok, acc}

  defp collect_all_messages(_thread, _base_opts, %MessagePage{next_cursor: ""}, acc, _seen),
    do: {:ok, acc}

  defp collect_all_messages(thread, base_opts, %MessagePage{next_cursor: cursor}, acc, seen)
       when is_binary(cursor) do
    if MapSet.member?(seen, cursor) do
      {:ok, acc}
    else
      next_opts = Keyword.put(base_opts, :cursor, cursor)

      with {:ok, %MessagePage{} = next_page} <- messages(thread, next_opts) do
        collect_all_messages(
          thread,
          base_opts,
          next_page,
          acc ++ next_page.messages,
          MapSet.put(seen, cursor)
        )
      end
    end
  end

  defp next_message_batch(%{pending: [next | rest]} = state),
    do: {[next], %{state | pending: rest}}

  defp next_message_batch(%{done?: true} = state), do: {:halt, state}

  defp next_message_batch(%{thread: thread, opts: opts, cursor: cursor} = state) do
    request_opts =
      case cursor do
        nil -> opts
        next_cursor -> Keyword.put(opts, :cursor, next_cursor)
      end

    case messages(thread, request_opts) do
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

  defp normalize_fetch_opts(%Jido.Chat.FetchOptions{} = opts),
    do: Jido.Chat.FetchOptions.to_keyword(opts)

  defp normalize_fetch_opts(opts) when is_map(opts),
    do: opts |> Jido.Chat.FetchOptions.new() |> Jido.Chat.FetchOptions.to_keyword()

  defp normalize_fetch_opts(opts) when is_list(opts),
    do: opts |> Jido.Chat.FetchOptions.new() |> Jido.Chat.FetchOptions.to_keyword()

  defp normalize_fetch_opts(_other),
    do: Jido.Chat.FetchOptions.to_keyword(Jido.Chat.FetchOptions.new(%{}))

  defp with_thread_opts(opts, %__MODULE__{} = thread), do: with_thread_opts(thread, opts)

  defp with_thread_opts(%__MODULE__{external_thread_id: nil}, opts), do: opts

  defp with_thread_opts(%__MODULE__{external_thread_id: external_thread_id}, opts) do
    Keyword.put_new(opts, :thread_id, external_thread_id)
  end

  defp maybe_put_status(opts, nil), do: opts
  defp maybe_put_status(opts, ""), do: opts
  defp maybe_put_status(opts, status), do: Keyword.put(opts, :status, status)

  defp external_user_id(%Author{user_id: user_id}) when is_binary(user_id), do: {:ok, user_id}
  defp external_user_id(user_id) when is_binary(user_id), do: {:ok, user_id}
  defp external_user_id(user_id) when is_integer(user_id), do: {:ok, user_id}

  defp external_user_id(%{} = map) do
    case map[:user_id] || map["user_id"] do
      nil -> {:error, :invalid_user}
      user_id -> {:ok, user_id}
    end
  end

  defp external_user_id(_), do: {:error, :invalid_user}

  defp mention_user_id(%Author{user_id: user_id}), do: user_id
  defp mention_user_id(%{} = user), do: user[:user_id] || user["user_id"] || "unknown"
  defp mention_user_id(user_id), do: user_id
end
