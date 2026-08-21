defmodule Jido.Chat.Adapter do
  @moduledoc """
  Canonical adapter behavior for Chat SDK style integrations.

  Thread-aware channel contract for Chat SDK integrations.

  Adapters return message edits and deletes from `c:parse_event/2` as
  `Jido.Chat.EventEnvelope` values with event type `:message_updated` or
  `:message_deleted`. The payload must include the provider `message_id` and
  should include channel, thread, author, timestamp, metadata, and raw provider
  context when available. An update should include the changed `message` when
  available. A delete must leave `message` as `nil` when the provider omits the
  deleted content. Core does not fetch missing deleted content.
  """

  alias Jido.Chat.{
    Author,
    CapabilityMatrix,
    Card,
    ChannelInfo,
    EphemeralMessage,
    EventEnvelope,
    FetchOptions,
    FileUpload,
    Incoming,
    Markdown,
    Media,
    Message,
    MessagePage,
    MessageSubject,
    Modal,
    ModalResult,
    Participant,
    Postable,
    PostPayload,
    Response,
    Thread,
    ThreadPage,
    UserInfo,
    WebhookRequest,
    WebhookResponse
  }

  alias Jido.Chat.Markdown.StreamRenderer

  @type raw_payload :: map()
  @type external_room_id :: String.t() | integer()
  @type external_user_id :: String.t() | integer()
  @type external_message_id :: String.t() | integer()
  @type sink_mfa :: {module(), atom(), [term()]}
  @type listener_opts :: keyword()

  @type capability_status :: :native | :fallback | :unsupported
  @type capability_matrix :: %{optional(atom()) => capability_status()}

  @capability_statuses [:native, :fallback, :unsupported]

  @type send_result :: {:ok, Response.t()} | {:error, term()}
  @type incoming_result :: {:ok, Incoming.t()} | {:error, term()}
  @type delete_result :: :ok | {:error, term()}
  @type typing_result :: :ok | {:error, term()}
  @type reaction_result :: :ok | {:error, term()}
  @type metadata_result :: {:ok, ChannelInfo.t()} | {:error, term()}
  @type message_result :: {:ok, Message.t()} | {:error, term()}
  @type message_page_result :: {:ok, MessagePage.t()} | {:error, term()}
  @type thread_result :: {:ok, Thread.t()} | {:error, term()}
  @type thread_page_result :: {:ok, ThreadPage.t()} | {:error, term()}
  @type ephemeral_result :: {:ok, EphemeralMessage.t()} | {:error, term()}
  @type modal_result :: {:ok, ModalResult.t()} | {:error, term()}
  @type media_result :: {:ok, binary()} | {:error, term()}
  @type user_result :: {:ok, UserInfo.t()} | {:error, term()}
  @type subject_result :: {:ok, MessageSubject.t()} | {:error, term()}
  @type participants_result :: {:ok, [Participant.t()]} | {:error, term()}
  @type read_result :: :ok | {:error, term()}
  @type file_input :: FileUpload.input()
  @type media_reference :: String.t() | Media.t() | map()

  @core_fallback_capabilities [
    :initialize,
    :shutdown,
    :post_message,
    :fetch_metadata,
    :fetch_thread,
    :post_channel_message,
    :stream,
    :webhook,
    :verify_webhook,
    :parse_event,
    :format_webhook_response
  ]

  @doc "Returns operations that always have a core fallback."
  @spec core_fallback_capabilities() :: [atom()]
  def core_fallback_capabilities, do: @core_fallback_capabilities

  @callback channel_type() :: atom()
  @callback transform_incoming(raw_payload()) :: incoming_result() | {:ok, map()}

  @callback send_message(external_room_id(), text :: String.t(), opts :: keyword()) ::
              send_result() | {:ok, map()} | {:error, term()}

  @callback send_file(external_room_id(), file :: file_input(), opts :: keyword()) ::
              send_result() | {:ok, map()} | {:error, term()}

  @callback post_message(external_room_id(), payload :: PostPayload.t(), opts :: keyword()) ::
              send_result() | {:ok, map()} | {:error, term()}

  @callback edit_message(
              external_room_id(),
              external_message_id(),
              text :: String.t(),
              opts :: keyword()
            ) ::
              send_result() | {:ok, map()} | {:error, term()}

  @callback initialize(opts :: keyword()) :: :ok | {:ok, term()} | {:error, term()}
  @callback shutdown(opts :: keyword()) :: :ok | {:ok, term()} | {:error, term()}

  @callback delete_message(external_room_id(), external_message_id(), opts :: keyword()) ::
              :ok | {:ok, term()} | {:error, term()}

  @callback start_typing(external_room_id(), opts :: keyword()) ::
              :ok | {:ok, term()} | {:error, term()}

  @callback fetch_metadata(external_room_id(), opts :: keyword()) ::
              {:ok, ChannelInfo.t() | map()} | {:error, term()}

  @callback fetch_thread(external_room_id(), opts :: keyword()) ::
              {:ok, Thread.t() | map()} | {:error, term()}

  @callback fetch_message(external_room_id(), external_message_id(), opts :: keyword()) ::
              {:ok, Message.t() | Incoming.t() | map()} | {:error, term()}

  @doc "Returns normalized information for one provider user."
  @callback get_user(external_user_id(), opts :: keyword()) ::
              {:ok, UserInfo.t() | map()} | {:error, term()}

  @doc "Returns the resource subject for a room or thread."
  @callback fetch_subject(external_room_id(), opts :: keyword()) ::
              {:ok, MessageSubject.t() | map()} | {:error, term()}

  @doc "Returns the canonical participants for a room or thread."
  @callback get_thread_participants(external_room_id(), opts :: keyword()) ::
              {:ok, [Participant.t() | UserInfo.t() | Author.t() | map()]} | {:error, term()}

  @doc "Marks a provider message as read. Repeated calls must be safe."
  @callback mark_as_read(
              external_room_id(),
              external_message_id(),
              opts :: keyword()
            ) :: :ok | {:ok, term()} | {:error, term()}

  @doc """
  Fetches the bytes behind an inbound media reference.

  The inbound counterpart to `c:send_file/3`. The reference is the one the adapter itself
  minted on the incoming message, so the adapter that created it is the one that resolves
  it — no caller ever learns a provider's reference scheme.
  """
  @callback fetch_media(reference :: media_reference(), opts :: keyword()) :: media_result()

  @callback add_reaction(
              external_room_id(),
              external_message_id(),
              emoji :: String.t(),
              opts :: keyword()
            ) ::
              :ok | {:ok, term()} | {:error, term()}

  @callback remove_reaction(
              external_room_id(),
              external_message_id(),
              emoji :: String.t(),
              opts :: keyword()
            ) ::
              :ok | {:ok, term()} | {:error, term()}

  @callback post_ephemeral(
              external_room_id(),
              external_user_id(),
              text :: String.t(),
              opts :: keyword()
            ) ::
              {:ok, EphemeralMessage.t() | map()} | {:error, term()}

  @callback post_channel_message(external_room_id(), text :: String.t(), opts :: keyword()) ::
              send_result() | {:ok, map()} | {:error, term()}

  @callback stream(external_room_id(), stream :: Enumerable.t(), opts :: keyword()) ::
              send_result() | {:ok, map()} | {:error, term()}

  @callback open_modal(external_room_id(), payload :: map(), opts :: keyword()) ::
              {:ok, ModalResult.t() | map()} | {:error, term()}

  @callback fetch_messages(external_room_id(), opts :: keyword()) ::
              {:ok, MessagePage.t() | map()} | {:error, term()}

  @callback fetch_channel_messages(external_room_id(), opts :: keyword()) ::
              {:ok, MessagePage.t() | map()} | {:error, term()}

  @callback list_threads(external_room_id(), opts :: keyword()) ::
              {:ok, ThreadPage.t() | map()} | {:error, term()}

  @callback open_thread(external_room_id(), external_message_id(), opts :: keyword()) ::
              {:ok, Thread.t() | map()} | {:error, term()}

  @callback open_dm(external_user_id(), opts :: keyword()) ::
              {:ok, external_room_id()} | {:error, term()}

  @callback handle_webhook(chat :: Jido.Chat.t(), raw_payload(), opts :: keyword()) ::
              {:ok, Jido.Chat.t(), Incoming.t()} | {:error, term()}

  @callback verify_webhook(WebhookRequest.t() | map(), opts :: keyword()) ::
              :ok | {:error, term()}

  @callback parse_event(WebhookRequest.t() | map(), opts :: keyword()) ::
              {:ok, EventEnvelope.t() | map() | :noop | nil} | {:error, term()}

  @callback format_webhook_response(term(), opts :: keyword()) ::
              WebhookResponse.t() | map() | {:ok, WebhookResponse.t() | map()} | {:error, term()}

  @doc """
  Optional listener child-spec callback for adapter-owned ingress workers.

  Listener workers should emit inbound payloads/events through a sink MFA provided
  in `opts` to avoid coupling adapter packages to runtime implementations.

  Expected listener opts keys:
    * `:sink_mfa` - sink callback MFA, typically `{Module, :function, [base_args...]}`
    * `:bridge_id` - configured bridge identifier
    * `:bridge_config` - resolved bridge config struct/map
    * `:instance_module` - runtime instance module (opaque to adapters)
    * `:settings` - adapter-specific ingress settings map
    * `:ingress` - normalized ingress mode/settings map
  """
  @callback listener_child_specs(bridge_id :: String.t(), opts :: listener_opts()) ::
              {:ok, [Supervisor.child_spec()]} | {:error, term()}

  @callback capabilities() :: capability_matrix()

  @optional_callbacks initialize: 1,
                      shutdown: 1,
                      send_file: 3,
                      post_message: 3,
                      edit_message: 4,
                      delete_message: 3,
                      start_typing: 2,
                      fetch_metadata: 2,
                      fetch_thread: 2,
                      fetch_message: 3,
                      get_user: 2,
                      fetch_subject: 2,
                      get_thread_participants: 2,
                      mark_as_read: 3,
                      fetch_media: 2,
                      add_reaction: 4,
                      remove_reaction: 4,
                      post_ephemeral: 4,
                      post_channel_message: 3,
                      stream: 3,
                      open_modal: 3,
                      fetch_messages: 2,
                      fetch_channel_messages: 2,
                      list_threads: 2,
                      open_thread: 3,
                      open_dm: 2,
                      handle_webhook: 3,
                      verify_webhook: 2,
                      parse_event: 2,
                      format_webhook_response: 2,
                      listener_child_specs: 2,
                      capabilities: 0

  defmacro __using__(_opts) do
    quote do
      @behaviour Jido.Chat.Adapter

      @impl true
      def channel_type do
        __MODULE__
        |> Module.split()
        |> List.last()
        |> Macro.underscore()
        |> String.to_atom()
      end

      defoverridable channel_type: 0
    end
  end

  @doc "Initializes adapter resources when supported."
  @spec initialize(module(), keyword()) :: :ok | {:error, term()}
  def initialize(adapter_module, opts \\ []) do
    if callback_exported?(adapter_module, :initialize, 1) do
      case adapter_module.initialize(opts) do
        :ok -> :ok
        {:ok, _} -> :ok
        {:error, _} = error -> error
        _ -> {:error, :invalid_initialize_result}
      end
    else
      :ok
    end
  end

  @doc "Shuts down adapter resources when supported."
  @spec shutdown(module(), keyword()) :: :ok | {:error, term()}
  def shutdown(adapter_module, opts \\ []) do
    if callback_exported?(adapter_module, :shutdown, 1) do
      case adapter_module.shutdown(opts) do
        :ok -> :ok
        {:ok, _} -> :ok
        {:error, _} = error -> error
        _ -> {:error, :invalid_shutdown_result}
      end
    else
      :ok
    end
  end

  @doc "Returns capability matrix for adapter-native vs fallback support."
  @spec capabilities(module()) :: capability_matrix()
  def capabilities(adapter_module) do
    declared =
      if callback_exported?(adapter_module, :capabilities, 0) do
        normalize_capability_matrix(adapter_module.capabilities())
      else
        %{}
      end

    ensure_capability_defaults(declared, adapter_module)
  end

  @doc "Normalizes adapter inbound transformation to `Jido.Chat.Incoming`."
  @spec transform_incoming(module(), raw_payload()) :: incoming_result()
  def transform_incoming(adapter_module, payload)
      when is_atom(adapter_module) and is_map(payload) do
    with {:ok, incoming} <- adapter_module.transform_incoming(payload) do
      {:ok, normalize_incoming(incoming)}
    end
  end

  @doc "Normalizes adapter send results to `Jido.Chat.Response`."
  @spec send_message(module(), external_room_id(), String.t(), keyword()) :: send_result()
  def send_message(adapter_module, external_room_id, text, opts \\ []) do
    with {:ok, response} <- adapter_module.send_message(external_room_id, text, opts) do
      {:ok, normalize_response(adapter_module, response)}
    end
  end

  @doc "Uploads and sends a file when supported by the adapter."
  @spec send_file(module(), external_room_id(), file_input(), keyword()) :: send_result()
  def send_file(adapter_module, external_room_id, file, opts \\ []) do
    if callback_exported?(adapter_module, :send_file, 3) do
      with {:ok, response} <- adapter_module.send_file(external_room_id, file, opts) do
        {:ok, normalize_response(adapter_module, response)}
      end
    else
      {:error, :unsupported}
    end
  end

  @doc "Posts a normalized outbound payload using adapter-native or core fallback behavior."
  @spec post_message(module(), external_room_id(), PostPayload.t() | map(), keyword()) ::
          send_result()
  def post_message(adapter_module, external_room_id, payload, opts \\ [])

  def post_message(adapter_module, external_room_id, %PostPayload{} = payload, opts) do
    scope = Keyword.get(opts, :scope, :thread)
    adapter_opts = Keyword.delete(opts, :scope)
    upload_candidates = PostPayload.upload_candidates(payload)

    cond do
      callback_exported?(adapter_module, :post_message, 3) ->
        with {:ok, response} <-
               adapter_module.post_message(external_room_id, payload, adapter_opts) do
          {:ok, normalize_response(adapter_module, response)}
        end

      upload_candidates in [nil, []] and scope == :channel ->
        post_channel_message(
          adapter_module,
          external_room_id,
          PostPayload.display_text(payload) || "",
          adapter_opts
        )

      upload_candidates in [nil, []] ->
        send_message(
          adapter_module,
          external_room_id,
          PostPayload.display_text(payload) || "",
          adapter_opts
        )

      match?([_single], upload_candidates) ->
        [upload] = upload_candidates

        file_opts =
          adapter_opts
          |> maybe_put_caption(payload)
          |> maybe_put_metadata(payload.metadata)

        send_file(adapter_module, external_room_id, upload, file_opts)

      true ->
        {:error, :multiple_attachments_unsupported}
    end
  end

  def post_message(adapter_module, external_room_id, payload, opts)
      when is_map(payload),
      do: post_message(adapter_module, external_room_id, PostPayload.new(payload), opts)

  @doc "Posts a channel-level message using adapter callback or send fallback."
  @spec post_channel_message(module(), external_room_id(), String.t(), keyword()) :: send_result()
  def post_channel_message(adapter_module, external_room_id, text, opts \\ []) do
    if callback_exported?(adapter_module, :post_channel_message, 3) do
      with {:ok, response} <- adapter_module.post_channel_message(external_room_id, text, opts) do
        {:ok, normalize_response(adapter_module, response)}
      end
    else
      send_message(adapter_module, external_room_id, text, opts)
    end
  end

  @doc """
  Streams chunked text with the adapter's native callback or a core fallback.

  Adapters with native or append-only transport receive the original enumerable and
  can use `Jido.Chat.Markdown.StreamRenderer` to build safe snapshots. Core fallback
  mode `:post_edit` posts once and edits safe snapshots. Mode `:final` posts the exact
  final Markdown once.
  """
  @spec stream(module(), external_room_id(), Enumerable.t(), keyword()) :: send_result()
  def stream(adapter_module, external_room_id, chunks, opts \\ []) do
    if callback_exported?(adapter_module, :stream, 3) do
      with {:ok, response} <- adapter_module.stream(external_room_id, chunks, opts) do
        {:ok, normalize_response(adapter_module, response)}
      end
    else
      fallback_chunks = Enum.to_list(chunks)
      fallback_mode = Keyword.get(opts, :fallback_mode, default_stream_fallback(adapter_module))
      placeholder_text = Keyword.get(opts, :placeholder_text, "Working...")
      update_every = Keyword.get(opts, :update_every, 1)
      stream_opts = Keyword.drop(opts, [:fallback_mode, :placeholder_text, :update_every])
      fallback_text = StreamRenderer.render(fallback_chunks)
      chunk_count = length(fallback_chunks)

      cond do
        is_nil(fallback_text) ->
          {:error, :empty_stream}

        fallback_mode == :post_edit and callback_exported?(adapter_module, :edit_message, 4) ->
          stream_post_edit_fallback(
            adapter_module,
            external_room_id,
            fallback_chunks,
            stream_opts,
            %{
              placeholder_text: placeholder_text,
              update_every: update_every,
              chunk_count: chunk_count,
              final_text: fallback_text
            }
          )

        true ->
          with {:ok, response} <-
                 send_message(adapter_module, external_room_id, fallback_text, stream_opts) do
            {:ok,
             with_stream_metadata(
               response,
               fallback_mode,
               chunk_count,
               fallback_text
             )}
          end
      end
    end
  end

  @doc "Renders a finite stream with the canonical provider-independent Markdown rules."
  @spec render_stream(Enumerable.t()) :: String.t() | nil
  def render_stream(chunks), do: StreamRenderer.render(chunks)

  @doc "Normalizes adapter edit results to `Jido.Chat.Response`."
  @spec edit_message(module(), external_room_id(), external_message_id(), String.t(), keyword()) ::
          send_result()
  def edit_message(adapter_module, external_room_id, external_message_id, text, opts \\ []) do
    if callback_exported?(adapter_module, :edit_message, 4) do
      with {:ok, response} <-
             adapter_module.edit_message(external_room_id, external_message_id, text, opts) do
        {:ok, normalize_response(adapter_module, Map.put(response, :status, :edited))}
      end
    else
      {:error, :unsupported}
    end
  end

  @doc "Deletes a previously-sent message when supported by adapter."
  @spec delete_message(module(), external_room_id(), external_message_id(), keyword()) ::
          delete_result()
  def delete_message(adapter_module, external_room_id, external_message_id, opts \\ []) do
    if callback_exported?(adapter_module, :delete_message, 3) do
      case adapter_module.delete_message(external_room_id, external_message_id, opts) do
        :ok -> :ok
        {:ok, _} -> :ok
        {:error, _} = error -> error
        _other -> {:error, :invalid_delete_result}
      end
    else
      {:error, :unsupported}
    end
  end

  @doc "Starts typing indicator when supported by adapter."
  @spec start_typing(module(), external_room_id(), keyword()) :: typing_result()
  def start_typing(adapter_module, external_room_id, opts \\ []) do
    if callback_exported?(adapter_module, :start_typing, 2) do
      case adapter_module.start_typing(external_room_id, opts) do
        :ok -> :ok
        {:ok, _} -> :ok
        {:error, _} = error -> error
        _other -> {:error, :invalid_typing_result}
      end
    else
      {:error, :unsupported}
    end
  end

  @doc "Fetches channel metadata as `Jido.Chat.ChannelInfo`."
  @spec fetch_metadata(module(), external_room_id(), keyword()) :: metadata_result()
  def fetch_metadata(adapter_module, external_room_id, opts \\ []) do
    if callback_exported?(adapter_module, :fetch_metadata, 2) do
      with {:ok, info} <- adapter_module.fetch_metadata(external_room_id, opts) do
        {:ok, normalize_channel_info(adapter_module, info, external_room_id)}
      end
    else
      {:ok, default_channel_info(adapter_module, external_room_id)}
    end
  end

  @doc "Fetches thread metadata as a normalized `Jido.Chat.Thread`."
  @spec fetch_thread(module(), external_room_id(), keyword()) :: thread_result()
  def fetch_thread(adapter_module, external_room_id, opts \\ []) do
    if callback_exported?(adapter_module, :fetch_thread, 2) do
      case adapter_module.fetch_thread(external_room_id, opts) do
        {:ok, thread} -> normalize_thread_result(adapter_module, thread, external_room_id, opts)
        {:error, _reason} = error -> error
        _other -> {:error, :invalid_thread_result}
      end
    else
      {:ok,
       Thread.new(%{
         id: opts[:thread_id] || "#{adapter_type(adapter_module)}:#{external_room_id}",
         adapter_name: adapter_type(adapter_module),
         adapter: adapter_module,
         external_room_id: external_room_id,
         external_thread_id: opts[:external_thread_id],
         metadata: %{}
       })}
    end
  end

  @doc "Fetches a normalized message by id when supported."
  @spec fetch_message(module(), external_room_id(), external_message_id(), keyword()) ::
          message_result()
  def fetch_message(adapter_module, external_room_id, external_message_id, opts \\ []) do
    if callback_exported?(adapter_module, :fetch_message, 3) do
      with {:ok, message} <-
             adapter_module.fetch_message(external_room_id, external_message_id, opts) do
        {:ok, normalize_message(adapter_module, message, opts)}
      end
    else
      {:error, :unsupported}
    end
  end

  @doc "Gets normalized provider user information when supported."
  @spec get_user(module(), external_user_id(), keyword()) :: user_result()
  def get_user(adapter_module, external_user_id, opts \\ []) do
    if callback_exported?(adapter_module, :get_user, 2) do
      case adapter_module.get_user(external_user_id, opts) do
        {:ok, user} -> normalize_user_result(user)
        {:error, _reason} = error -> error
        _other -> {:error, :invalid_user_info_result}
      end
    else
      {:error, :unsupported}
    end
  end

  @doc "Fetches the normalized resource subject for a room or thread."
  @spec fetch_subject(module(), external_room_id(), keyword()) :: subject_result()
  def fetch_subject(adapter_module, external_room_id, opts \\ []) do
    cond do
      callback_exported?(adapter_module, :fetch_subject, 2) ->
        case adapter_module.fetch_subject(external_room_id, opts) do
          {:ok, subject} -> normalize_subject_result(subject)
          {:error, _reason} = error -> error
          _other -> {:error, :invalid_subject_result}
        end

      callback_exported?(adapter_module, :fetch_thread, 2) ->
        with {:ok, thread} <- fetch_thread(adapter_module, external_room_id, opts),
             {:ok, subject} <- explicit_thread_subject(thread) do
          normalize_subject_result(subject)
        end

      true ->
        {:error, :unsupported}
    end
  end

  @doc "Gets normalized canonical participants for a room or thread."
  @spec get_thread_participants(module(), external_room_id(), keyword()) ::
          participants_result()
  def get_thread_participants(adapter_module, external_room_id, opts \\ []) do
    if callback_exported?(adapter_module, :get_thread_participants, 2) do
      case adapter_module.get_thread_participants(external_room_id, opts) do
        {:ok, participants} when is_list(participants) ->
          normalize_participants_result(adapter_module, participants)

        {:error, _reason} = error ->
          error

        _other ->
          {:error, :invalid_thread_participants_result}
      end
    else
      {:error, :unsupported}
    end
  end

  @doc "Marks a provider message as read when supported."
  @spec mark_as_read(module(), external_room_id(), external_message_id(), keyword()) ::
          read_result()
  def mark_as_read(adapter_module, external_room_id, external_message_id, opts \\ []) do
    if callback_exported?(adapter_module, :mark_as_read, 3) do
      case adapter_module.mark_as_read(external_room_id, external_message_id, opts) do
        :ok -> :ok
        {:ok, _receipt} -> :ok
        {:error, _reason} = error -> error
        _other -> {:error, :invalid_mark_as_read_result}
      end
    else
      {:error, :unsupported}
    end
  end

  @doc "Fetches media bytes when supported by the adapter."
  @spec fetch_media(module(), media_reference(), keyword()) :: media_result()
  def fetch_media(adapter_module, reference, opts \\ []) do
    if callback_exported?(adapter_module, :fetch_media, 2) do
      case adapter_module.fetch_media(reference, opts) do
        {:ok, bytes} when is_binary(bytes) -> {:ok, bytes}
        {:ok, _other} -> {:error, :invalid_media_result}
        {:error, _reason} = error -> error
        _other -> {:error, :invalid_media_result}
      end
    else
      {:error, :unsupported}
    end
  end

  @doc "Adds a reaction when supported by adapter."
  @spec add_reaction(module(), external_room_id(), external_message_id(), String.t(), keyword()) ::
          reaction_result()
  def add_reaction(adapter_module, external_room_id, external_message_id, emoji, opts \\ []) do
    if callback_exported?(adapter_module, :add_reaction, 4) do
      case adapter_module.add_reaction(external_room_id, external_message_id, emoji, opts) do
        :ok -> :ok
        {:ok, _} -> :ok
        {:error, _} = error -> error
        _other -> {:error, :invalid_reaction_result}
      end
    else
      {:error, :unsupported}
    end
  end

  @doc "Removes a reaction when supported by adapter."
  @spec remove_reaction(
          module(),
          external_room_id(),
          external_message_id(),
          String.t(),
          keyword()
        ) ::
          reaction_result()
  def remove_reaction(adapter_module, external_room_id, external_message_id, emoji, opts \\ []) do
    if callback_exported?(adapter_module, :remove_reaction, 4) do
      case adapter_module.remove_reaction(external_room_id, external_message_id, emoji, opts) do
        :ok -> :ok
        {:ok, _} -> :ok
        {:error, _} = error -> error
        _other -> {:error, :invalid_reaction_result}
      end
    else
      {:error, :unsupported}
    end
  end

  @doc "Posts an ephemeral message when supported, with optional DM fallback."
  @spec post_ephemeral(module(), external_room_id(), external_user_id(), String.t(), keyword()) ::
          ephemeral_result()
  def post_ephemeral(adapter_module, external_room_id, external_user_id, text, opts \\ []) do
    post_ephemeral_message(
      adapter_module,
      external_room_id,
      external_user_id,
      PostPayload.text(text),
      opts
    )
  end

  @doc "Posts an ephemeral payload using the canonical outbound payload contract."
  @spec post_ephemeral_message(
          module(),
          external_room_id(),
          external_user_id(),
          String.t() | Postable.t() | PostPayload.t() | map(),
          keyword()
        ) :: ephemeral_result()
  def post_ephemeral_message(
        adapter_module,
        external_room_id,
        external_user_id,
        input,
        opts \\ []
      ) do
    with {:ok, payload} <- normalize_post_payload_input(input) do
      upload_candidates = PostPayload.upload_candidates(payload)
      text = PostPayload.display_text(payload) || ""
      base_opts = maybe_put_metadata(opts, payload.metadata)
      fallback_to_dm = Keyword.get(base_opts, :fallback_to_dm, false)

      cond do
        upload_candidates == [] and callback_exported?(adapter_module, :post_ephemeral, 4) ->
          with {:ok, message} <-
                 adapter_module.post_ephemeral(
                   external_room_id,
                   external_user_id,
                   text,
                   base_opts
                 ) do
            {:ok,
             normalize_ephemeral(
               adapter_module,
               message,
               external_room_id,
               false,
               payload,
               base_opts
             )}
          end

        fallback_to_dm and callback_exported?(adapter_module, :open_dm, 2) ->
          dm_opts = Keyword.delete(base_opts, :fallback_to_dm)

          with {:ok, dm_room_id} <- adapter_module.open_dm(external_user_id, base_opts),
               {:ok, response} <- post_message(adapter_module, dm_room_id, payload, dm_opts) do
            {:ok,
             EphemeralMessage.new(%{
               id: response.external_message_id || Jido.Chat.ID.generate!(),
               thread_id: fallback_thread_id(adapter_module, dm_room_id),
               text: text,
               formatted: payload.formatted || text,
               used_fallback: true,
               raw: response.raw,
               attachments: PostPayload.outbound_attachments(payload),
               metadata:
                 %{source_room_id: external_room_id, delivery: :dm_fallback}
                 |> Map.merge(payload.metadata)
             })}
          end

        upload_candidates != [] ->
          {:error, :ephemeral_attachments_unsupported}

        true ->
          {:error, :unsupported}
      end
    end
  end

  @doc "Opens adapter-native modal when supported."
  @spec open_modal(module(), external_room_id(), Modal.t() | map(), keyword()) ::
          modal_result()
  def open_modal(adapter_module, external_room_id, payload, opts \\ [])
      when is_map(payload) or is_struct(payload, Modal) do
    payload = normalize_modal_payload(payload)

    if callback_exported?(adapter_module, :open_modal, 3) do
      with {:ok, result} <- adapter_module.open_modal(external_room_id, payload, opts) do
        {:ok, normalize_modal_result(result, external_room_id)}
      end
    else
      {:error, :unsupported}
    end
  end

  @doc "Fetches thread-level history when supported by adapter."
  @spec fetch_messages(module(), external_room_id(), keyword()) :: message_page_result()
  def fetch_messages(adapter_module, external_room_id, opts \\ []) do
    if callback_exported?(adapter_module, :fetch_messages, 2) do
      fetch_opts = normalize_fetch_opts(opts)

      with {:ok, page} <-
             adapter_module.fetch_messages(external_room_id, FetchOptions.to_keyword(fetch_opts)) do
        {:ok, normalize_message_page(adapter_module, page, fetch_opts, external_room_id, opts)}
      end
    else
      {:error, :unsupported}
    end
  end

  @doc "Fetches channel-level history when supported by adapter."
  @spec fetch_channel_messages(module(), external_room_id(), keyword()) :: message_page_result()
  def fetch_channel_messages(adapter_module, external_room_id, opts \\ []) do
    if callback_exported?(adapter_module, :fetch_channel_messages, 2) do
      fetch_opts = normalize_fetch_opts(opts)

      with {:ok, page} <-
             adapter_module.fetch_channel_messages(
               external_room_id,
               FetchOptions.to_keyword(fetch_opts)
             ) do
        {:ok, normalize_message_page(adapter_module, page, fetch_opts, external_room_id, opts)}
      end
    else
      {:error, :unsupported}
    end
  end

  @doc "Lists channel thread summaries when supported by adapter."
  @spec list_threads(module(), external_room_id(), keyword()) :: thread_page_result()
  def list_threads(adapter_module, external_room_id, opts \\ []) do
    if callback_exported?(adapter_module, :list_threads, 2) do
      with {:ok, page} <- adapter_module.list_threads(external_room_id, opts) do
        {:ok, normalize_thread_page(page)}
      end
    else
      {:error, :unsupported}
    end
  end

  @doc "Opens a native platform thread from an existing room message when supported."
  @spec open_thread(module(), external_room_id(), external_message_id(), keyword()) ::
          thread_result()
  def open_thread(adapter_module, external_room_id, external_message_id, opts \\ []) do
    if callback_exported?(adapter_module, :open_thread, 3) do
      with {:ok, thread} <-
             adapter_module.open_thread(external_room_id, external_message_id, opts) do
        {:ok, normalize_thread(adapter_module, thread, external_room_id, opts)}
      end
    else
      {:error, :unsupported}
    end
  end

  @doc "Default helper to normalize webhook payload through `transform_incoming/1`."
  @spec handle_webhook(module(), Jido.Chat.t(), raw_payload(), keyword()) ::
          {:ok, Jido.Chat.t(), Incoming.t()} | {:error, term()}
  def handle_webhook(adapter_module, %Jido.Chat{} = chat, payload, opts \\ []) do
    with {:ok, incoming} <- transform_incoming(adapter_module, payload) do
      thread_id = thread_id(adapter_module, incoming, opts)
      Jido.Chat.process_message(chat, adapter_type(adapter_module), thread_id, incoming, opts)
    end
  end

  @doc "Verifies webhook request integrity when adapter exposes validation callback."
  @spec verify_webhook(module(), WebhookRequest.t() | map(), keyword()) ::
          :ok | {:error, term()}
  def verify_webhook(adapter_module, request, opts \\ []) do
    request = normalize_webhook_request(request, opts)

    if callback_exported?(adapter_module, :verify_webhook, 2) do
      adapter_module.verify_webhook(request, opts)
    else
      :ok
    end
  end

  @doc "Parses request into a normalized event envelope."
  @spec parse_event(module(), WebhookRequest.t() | map(), keyword()) ::
          {:ok, EventEnvelope.t() | :noop} | {:error, term()}
  def parse_event(adapter_module, request, opts \\ []) do
    request = normalize_webhook_request(request, opts)

    cond do
      callback_exported?(adapter_module, :parse_event, 2) ->
        case adapter_module.parse_event(request, opts) do
          {:ok, :noop} ->
            {:ok, :noop}

          {:ok, nil} ->
            {:ok, :noop}

          {:ok, parsed} ->
            {:ok, normalize_event_envelope(adapter_module, parsed)}

          {:error, _reason} = error ->
            error
        end

      true ->
        with {:ok, incoming} <- transform_incoming(adapter_module, request.payload) do
          {:ok,
           EventEnvelope.new(%{
             adapter_name: adapter_type(adapter_module),
             event_type: :message,
             thread_id: thread_id(adapter_module, incoming, opts),
             channel_id: stringify(incoming.external_room_id),
             message_id: stringify(incoming.external_message_id),
             payload: incoming,
             raw: request.payload,
             metadata: %{path: request.path, method: request.method}
           })}
        end
    end
  end

  @doc "Formats a typed webhook response using adapter callback when available."
  @spec format_webhook_response(module(), term(), keyword()) ::
          {:ok, WebhookResponse.t()} | {:error, term()}
  def format_webhook_response(adapter_module, result, opts \\ []) do
    if callback_exported?(adapter_module, :format_webhook_response, 2) do
      case adapter_module.format_webhook_response(result, opts) do
        {:ok, response} ->
          {:ok, normalize_webhook_response(response)}

        %WebhookResponse{} = response ->
          {:ok, response}

        response when is_map(response) ->
          {:ok, WebhookResponse.new(response)}

        {:error, _} = error ->
          error

        _other ->
          {:error, :invalid_webhook_response}
      end
    else
      {:ok, default_webhook_response(result)}
    end
  end

  @doc "Returns a normalized typed capability matrix."
  @spec capability_matrix(module()) :: CapabilityMatrix.t()
  def capability_matrix(adapter_module) do
    CapabilityMatrix.new(%{
      adapter_name: adapter_type(adapter_module),
      capabilities: capabilities(adapter_module)
    })
  end

  @doc "Validates capability declaration coherence with implemented callbacks."
  @spec validate_capabilities(module()) :: :ok | {:error, term()}
  def validate_capabilities(adapter_module) do
    with {:ok, raw_declared} <- raw_capability_declaration(adapter_module) do
      invalid =
        adapter_module
        |> capabilities()
        |> Enum.reduce([], fn {capability, status}, acc ->
          callback = capability_callback(capability)

          case callback do
            nil ->
              acc

            {name, arity} ->
              exported? = callback_exported?(adapter_module, name, arity)
              declared_status = Map.get(raw_declared, capability, status)

              case {declared_status, exported?} do
                {:native, false} ->
                  [{capability, :missing_callback} | acc]

                {:fallback, false} ->
                  if fallback_available?(adapter_module, capability) do
                    acc
                  else
                    [{capability, :missing_fallback} | acc]
                  end

                {:unsupported, true} ->
                  [{capability, :unsupported_callback} | acc]

                _ ->
                  acc
              end
          end
        end)

      case invalid do
        [] -> :ok
        _ -> {:error, {:invalid_capability_matrix, Enum.reverse(invalid)}}
      end
    end
  end

  @doc "Returns adapter channel type with fallback to module name."
  @spec adapter_type(module()) :: atom()
  def adapter_type(adapter_module) do
    if callback_exported?(adapter_module, :channel_type, 0) do
      adapter_module.channel_type()
    else
      adapter_module
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
      |> String.to_atom()
    end
  end

  defp support_status(adapter_module, callback, arity, fallback \\ :unsupported) do
    if callback_exported?(adapter_module, callback, arity), do: :native, else: fallback
  end

  defp inferred_capability_status(adapter_module, capability) do
    case capability_callback(capability) do
      {callback, arity} ->
        fallback = if core_fallback_capability?(capability), do: :fallback, else: :unsupported
        support_status(adapter_module, callback, arity, fallback)

      nil ->
        :unsupported
    end
  end

  defp core_fallback_capability?(capability), do: capability in @core_fallback_capabilities

  defp fallback_available?(adapter_module, :fetch_subject),
    do: callback_exported?(adapter_module, :fetch_thread, 2)

  defp fallback_available?(_adapter_module, capability),
    do: core_fallback_capability?(capability)

  defp supported_status?(status), do: status in [:native, :fallback]

  defp normalize_capability_matrix(matrix) when is_map(matrix),
    do: matrix |> then(&CapabilityMatrix.new(%{capabilities: &1})) |> CapabilityMatrix.as_map()

  defp normalize_capability_matrix(_), do: %{}

  defp raw_capability_declaration(adapter_module) do
    if callback_exported?(adapter_module, :capabilities, 0) do
      case adapter_module.capabilities() do
        declaration when is_map(declaration) -> validate_capability_statuses(declaration)
        _other -> {:error, {:invalid_capability_matrix, [capabilities: :invalid_map]}}
      end
    else
      {:ok, %{}}
    end
  end

  defp validate_capability_statuses(declaration) do
    invalid =
      Enum.reduce(declaration, [], fn {capability, status}, acc ->
        if status in @capability_statuses do
          acc
        else
          [{capability, :invalid_status} | acc]
        end
      end)

    case invalid do
      [] -> {:ok, declaration}
      _ -> {:error, {:invalid_capability_matrix, Enum.reverse(invalid)}}
    end
  end

  defp normalize_incoming(%Incoming{} = incoming), do: incoming
  defp normalize_incoming(map) when is_map(map), do: Incoming.new(map)

  defp normalize_response(adapter_module, %Response{} = response) do
    response
    |> Map.put(:channel_type, Map.get(response, :channel_type) || adapter_type(adapter_module))
    |> Response.new()
  end

  defp normalize_response(adapter_module, map) when is_map(map) do
    map
    |> Map.put(
      :channel_type,
      Map.get(map, :channel_type) || Map.get(map, "channel_type") || adapter_type(adapter_module)
    )
    |> Response.new()
  end

  defp normalize_channel_info(_adapter_module, %ChannelInfo{} = info, _external_room_id), do: info

  defp normalize_channel_info(_adapter_module, info, external_room_id) when is_map(info) do
    info
    |> Map.put_new(:id, to_string(external_room_id))
    |> Map.put_new(:metadata, %{})
    |> Map.put_new(:name, nil)
    |> Map.put_new(:is_dm, nil)
    |> Map.put_new(:member_count, nil)
    |> Map.drop([:adapter_name])
    |> ChannelInfo.new()
  end

  defp normalize_channel_info(adapter_module, _info, external_room_id) do
    default_channel_info(adapter_module, external_room_id)
  end

  defp normalize_thread(_adapter_module, %Thread{} = thread, _external_room_id, _opts), do: thread

  defp normalize_thread(adapter_module, thread, external_room_id, opts) when is_map(thread) do
    external_thread_id =
      thread[:external_thread_id] || thread["external_thread_id"] || opts[:external_thread_id]

    metadata =
      (thread[:metadata] || thread["metadata"] || %{})
      |> maybe_put_thread_metadata(
        :delivery_external_room_id,
        thread[:delivery_external_room_id] || thread["delivery_external_room_id"]
      )

    Thread.new(%{
      id:
        thread[:id] || thread["id"] ||
          default_thread_id(adapter_module, external_room_id, external_thread_id),
      adapter_name: thread[:adapter_name] || thread["adapter_name"] || adapter_type(adapter_module),
      adapter: thread[:adapter] || thread["adapter"] || adapter_module,
      external_room_id: thread[:external_room_id] || thread["external_room_id"] || external_room_id,
      external_thread_id: external_thread_id,
      channel_id: thread[:channel_id] || thread["channel_id"],
      is_dm: thread[:is_dm] || thread["is_dm"] || false,
      metadata: metadata
    })
  end

  defp normalize_thread_result(adapter_module, thread, external_room_id, opts) do
    {:ok, normalize_thread(adapter_module, thread, external_room_id, opts)}
  rescue
    _error -> {:error, :invalid_thread_result}
  end

  defp normalize_message(_adapter_module, %Message{} = message, _opts), do: message

  defp normalize_message(adapter_module, %Incoming{} = incoming, opts),
    do:
      Message.from_incoming(incoming,
        adapter_name: adapter_type(adapter_module),
        thread_id: opts[:thread_id]
      )

  defp normalize_message(adapter_module, map, opts) when is_map(map) do
    if Map.has_key?(map, :external_room_id) || Map.has_key?(map, "external_room_id") do
      map
      |> Incoming.new()
      |> Message.from_incoming(
        adapter_name: adapter_type(adapter_module),
        thread_id: opts[:thread_id]
      )
    else
      map
      |> Map.put_new(:thread_id, opts[:thread_id])
      |> Message.new()
    end
  end

  defp normalize_user_result(%UserInfo{} = user), do: {:ok, user}

  defp normalize_user_result(user) when is_map(user) do
    {:ok, UserInfo.new(user)}
  rescue
    _error -> {:error, :invalid_user_info_result}
  end

  defp normalize_user_result(_user), do: {:error, :invalid_user_info_result}

  defp normalize_subject_result(%MessageSubject{} = subject), do: {:ok, subject}

  defp normalize_subject_result(subject) when is_map(subject) do
    {:ok, MessageSubject.new(subject)}
  rescue
    _error -> {:error, :invalid_subject_result}
  end

  defp normalize_subject_result(_subject), do: {:error, :invalid_subject_result}

  defp explicit_thread_subject(%Thread{metadata: metadata}) when is_map(metadata) do
    case metadata[:subject] || metadata["subject"] do
      nil -> {:error, :unsupported}
      subject -> {:ok, subject}
    end
  end

  defp normalize_participants_result(adapter_module, participants) do
    participants
    |> Enum.reduce_while({:ok, []}, fn participant, {:ok, acc} ->
      case normalize_participant(adapter_module, participant) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      {:error, _reason} = error -> error
    end
  end

  defp normalize_participant(_adapter_module, %Participant{} = participant),
    do: {:ok, participant}

  defp normalize_participant(adapter_module, %UserInfo{} = user) do
    {:ok, participant_from_user(adapter_module, user)}
  end

  defp normalize_participant(adapter_module, %Author{} = author) do
    user =
      UserInfo.new(%{
        id: author.user_id,
        username: author.user_name,
        display_name: author.full_name,
        is_bot: author.is_bot,
        metadata: author.metadata
      })

    {:ok, participant_from_user(adapter_module, user)}
  rescue
    _error -> {:error, :invalid_thread_participants_result}
  end

  defp normalize_participant(adapter_module, participant) when is_map(participant) do
    if participant_input?(participant) do
      {:ok, participant |> normalize_participant_attrs() |> Participant.new()}
    else
      {:ok, participant_from_user(adapter_module, UserInfo.new(participant))}
    end
  rescue
    _error -> {:error, :invalid_thread_participants_result}
  end

  defp normalize_participant(_adapter_module, _participant),
    do: {:error, :invalid_thread_participants_result}

  defp participant_from_user(adapter_module, %UserInfo{} = user) do
    identity =
      %{
        username: user.username,
        display_name: user.display_name,
        email: user.email,
        avatar_url: user.avatar_url
      }
      |> Map.filter(fn {_key, value} -> not is_nil(value) end)

    Participant.new(%{
      id: user.id,
      type: if(user.is_bot, do: :agent, else: :human),
      identity: identity,
      external_ids: %{adapter_type(adapter_module) => user.id},
      metadata: user.metadata
    })
  end

  defp participant_input?(participant) do
    id = participant[:id] || participant["id"]
    type = participant[:type] || participant["type"]

    not is_nil(id) and canonical_participant_type?(type)
  end

  defp canonical_participant_type?(type), do: type in [:human, :agent, :system, "human", "agent", "system"]

  defp normalize_participant_attrs(participant) do
    type = participant[:type] || participant["type"]

    participant
    |> Map.delete("type")
    |> Map.put(:type, normalize_participant_type(type))
  end

  defp normalize_participant_type(type) when type in [:human, :agent, :system], do: type
  defp normalize_participant_type("human"), do: :human
  defp normalize_participant_type("agent"), do: :agent
  defp normalize_participant_type("system"), do: :system
  defp normalize_participant_type(type), do: type

  defp normalize_message_page(
         _adapter_module,
         %MessagePage{} = page,
         _fetch_opts,
         _external_room_id,
         _opts
       ),
       do: page

  defp normalize_message_page(
         adapter_module,
         page,
         %FetchOptions{} = fetch_opts,
         external_room_id,
         opts
       )
       when is_map(page) do
    thread_opt =
      if is_list(opts) do
        Keyword.get(opts, :thread_id)
      else
        opts[:thread_id] || opts["thread_id"]
      end

    thread_id =
      thread_opt ||
        "#{adapter_type(adapter_module)}:#{external_room_id}"

    page
    |> Map.put_new(:direction, fetch_opts.direction)
    |> Map.put_new(:adapter_name, adapter_type(adapter_module))
    |> Map.put_new(:thread_id, thread_id)
    |> MessagePage.new()
  end

  defp normalize_thread_page(%ThreadPage{} = page), do: page
  defp normalize_thread_page(page) when is_map(page), do: ThreadPage.new(page)

  defp maybe_put_thread_metadata(metadata, _key, nil), do: metadata
  defp maybe_put_thread_metadata(metadata, key, value), do: Map.put(metadata, key, value)

  defp normalize_ephemeral(
         _adapter_module,
         %EphemeralMessage{} = message,
         _external_room_id,
         _used_fallback,
         _payload,
         _opts
       ),
       do: message

  defp normalize_ephemeral(
         adapter_module,
         message,
         external_room_id,
         used_fallback,
         payload,
         opts
       )
       when is_map(message) do
    thread_id =
      message[:thread_id] || message["thread_id"] ||
        fallback_thread_id(adapter_module, external_room_id)

    id =
      message[:id] || message["id"] ||
        message[:external_message_id] || message["external_message_id"] ||
        Jido.Chat.ID.generate!()

    EphemeralMessage.new(%{
      id: to_string(id),
      thread_id: to_string(thread_id),
      text: message[:text] || message["text"] || PostPayload.display_text(payload),
      formatted:
        message[:formatted] || message["formatted"] || payload.formatted ||
          PostPayload.display_text(payload),
      used_fallback: message[:used_fallback] || message["used_fallback"] || used_fallback,
      raw: message[:raw] || message["raw"],
      attachments:
        message[:attachments] || message["attachments"] ||
          PostPayload.outbound_attachments(payload),
      metadata:
        (message[:metadata] || message["metadata"] || %{})
        |> Map.merge(payload.metadata)
        |> Map.merge(metadata_from_opts(opts))
    })
  end

  defp normalize_modal_result(%ModalResult{} = result, _external_room_id), do: result

  defp normalize_modal_result(result, external_room_id) when is_map(result) do
    ModalResult.new(%{
      id: result[:id] || result["id"] || Jido.Chat.ID.generate!(),
      status: result[:status] || result["status"] || :opened,
      external_room_id: result[:external_room_id] || result["external_room_id"] || external_room_id,
      external_message_id: stringify(result[:external_message_id] || result["external_message_id"]),
      raw: result[:raw] || result["raw"],
      metadata: result[:metadata] || result["metadata"] || %{}
    })
  end

  defp normalize_modal_result(result, external_room_id) do
    ModalResult.new(%{
      external_room_id: external_room_id,
      raw: result,
      metadata: %{coerced: true}
    })
  end

  @doc "Returns a stable adapter-facing Markdown representation."
  @spec render_markdown(Markdown.t() | map() | String.t(), keyword()) :: String.t()
  def render_markdown(markdown, _opts \\ []) do
    markdown
    |> normalize_markdown_payload()
    |> Markdown.stringify()
  end

  @doc "Returns a stable adapter-facing card payload."
  @spec render_card(Card.t() | map(), keyword()) :: map()
  def render_card(card, _opts \\ []) do
    card
    |> normalize_card_payload()
    |> Card.to_adapter_payload()
  end

  @doc "Returns a stable adapter-facing modal payload."
  @spec render_modal(Modal.t() | map(), keyword()) :: map()
  def render_modal(modal, _opts \\ []) do
    modal
    |> normalize_modal_payload()
  end

  defp default_channel_info(adapter_module, external_room_id) do
    ChannelInfo.new(%{
      id: to_string(external_room_id),
      metadata: %{adapter_name: adapter_type(adapter_module)}
    })
  end

  defp default_thread_id(adapter_module, external_room_id, nil),
    do: "#{adapter_type(adapter_module)}:#{external_room_id}"

  defp default_thread_id(adapter_module, external_room_id, external_thread_id),
    do: "#{adapter_type(adapter_module)}:#{external_room_id}:#{external_thread_id}"

  defp normalize_fetch_opts(%FetchOptions{} = opts), do: opts
  defp normalize_fetch_opts(opts) when is_list(opts), do: FetchOptions.new(opts)
  defp normalize_fetch_opts(opts) when is_map(opts), do: FetchOptions.new(opts)
  defp normalize_fetch_opts(_other), do: FetchOptions.new(%{})

  defp thread_id(adapter_module, %Incoming{} = incoming, opts) do
    opts[:thread_id] || incoming.external_thread_id ||
      "#{adapter_type(adapter_module)}:#{incoming.external_room_id}"
  end

  defp fallback_thread_id(adapter_module, external_room_id),
    do: "#{adapter_type(adapter_module)}:#{external_room_id}"

  defp default_stream_fallback(adapter_module) do
    if callback_exported?(adapter_module, :edit_message, 4), do: :post_edit, else: :final
  end

  defp stream_post_edit_fallback(
         adapter_module,
         external_room_id,
         chunks,
         stream_opts,
         stream_state
       ) do
    update_every = normalize_update_every(stream_state.update_every)

    with {:ok, initial} <-
           start_stream_edit(adapter_module, external_room_id, stream_opts, stream_state.placeholder_text),
         {:ok, streamed} <-
           apply_stream_chunks(
             adapter_module,
             external_room_id,
             chunks,
             stream_opts,
             update_every,
             initial
           ),
         {:ok, completed} <-
           apply_stream_text(
             adapter_module,
             external_room_id,
             stream_opts,
             streamed,
             stream_state.final_text
           ) do
      {:ok,
       with_stream_metadata(
         completed.response,
         :post_edit,
         stream_state.chunk_count,
         stream_state.final_text
       )}
    end
  end

  defp start_stream_edit(adapter_module, external_room_id, stream_opts, placeholder_text) do
    if nonblank?(placeholder_text) do
      with {:ok, response} <-
             send_message(adapter_module, external_room_id, placeholder_text, stream_opts) do
        {:ok, %{renderer: StreamRenderer.new(), response: response, last_text: placeholder_text}}
      end
    else
      {:ok, %{renderer: StreamRenderer.new(), response: nil, last_text: nil}}
    end
  end

  defp apply_stream_chunks(
         adapter_module,
         external_room_id,
         chunks,
         stream_opts,
         update_every,
         initial
       ) do
    total = length(chunks)

    chunks
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, initial}, fn {chunk, index}, {:ok, state} ->
      boundary? = rem(index, update_every) == 0 or index == total

      {renderer, text} =
        if boundary? do
          {renderer, _update} = StreamRenderer.push(state.renderer, chunk)
          {renderer, StreamRenderer.snapshot(renderer)}
        else
          {StreamRenderer.append(state.renderer, chunk), nil}
        end

      state = %{state | renderer: renderer}

      case apply_stream_text(adapter_module, external_room_id, stream_opts, state, text) do
        {:ok, next_state} -> {:cont, {:ok, next_state}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp apply_stream_text(_adapter_module, _external_room_id, _stream_opts, state, nil),
    do: {:ok, state}

  defp apply_stream_text(_adapter_module, _external_room_id, _stream_opts, %{last_text: text} = state, text),
    do: {:ok, state}

  defp apply_stream_text(adapter_module, external_room_id, stream_opts, %{response: nil} = state, text) do
    with {:ok, response} <- send_message(adapter_module, external_room_id, text, stream_opts) do
      {:ok, %{state | response: response, last_text: text}}
    end
  end

  defp apply_stream_text(adapter_module, external_room_id, stream_opts, state, text) do
    with {:ok, response} <-
           edit_message(
             adapter_module,
             external_room_id,
             state.response.external_message_id,
             text,
             stream_opts
           ) do
      {:ok, %{state | response: response, last_text: text}}
    end
  end

  defp with_stream_metadata(%Response{} = response, mode, chunk_count, final_text) do
    metadata =
      response.metadata
      |> Map.put(:stream_fallback, mode)
      |> Map.put(:chunk_count, chunk_count)
      |> Map.put(:final_text, final_text)

    %{response | metadata: metadata}
  end

  defp normalize_update_every(value) when is_integer(value) and value > 0, do: value
  defp normalize_update_every(_value), do: 1

  defp nonblank?(text) when is_binary(text), do: String.trim(text) != ""
  defp nonblank?(_text), do: false

  defp normalize_markdown_payload(%Markdown{} = markdown), do: markdown
  defp normalize_markdown_payload(%{} = markdown), do: Markdown.new(markdown)
  defp normalize_markdown_payload(value) when is_binary(value), do: Markdown.parse(value)

  defp normalize_card_payload(%Card{} = card), do: card
  defp normalize_card_payload(%{} = card), do: Card.new(card)

  defp normalize_modal_payload(%Modal{} = modal), do: Modal.to_adapter_payload(modal)
  defp normalize_modal_payload(%{} = modal), do: modal

  defp ensure_capability_defaults(matrix, adapter_module) do
    defaults = %{
      initialize: inferred_capability_status(adapter_module, :initialize),
      shutdown: inferred_capability_status(adapter_module, :shutdown),
      send_message: :native,
      send_file: inferred_capability_status(adapter_module, :send_file),
      post_message: inferred_capability_status(adapter_module, :post_message),
      edit_message: inferred_capability_status(adapter_module, :edit_message),
      delete_message: inferred_capability_status(adapter_module, :delete_message),
      start_typing: inferred_capability_status(adapter_module, :start_typing),
      fetch_metadata: inferred_capability_status(adapter_module, :fetch_metadata),
      fetch_thread: inferred_capability_status(adapter_module, :fetch_thread),
      fetch_message: inferred_capability_status(adapter_module, :fetch_message),
      get_user: inferred_capability_status(adapter_module, :get_user),
      fetch_subject: subject_support_status(adapter_module),
      get_thread_participants: inferred_capability_status(adapter_module, :get_thread_participants),
      mark_as_read: inferred_capability_status(adapter_module, :mark_as_read),
      fetch_media: inferred_capability_status(adapter_module, :fetch_media),
      add_reaction: inferred_capability_status(adapter_module, :add_reaction),
      remove_reaction: inferred_capability_status(adapter_module, :remove_reaction),
      post_ephemeral: inferred_capability_status(adapter_module, :post_ephemeral),
      open_dm: inferred_capability_status(adapter_module, :open_dm),
      fetch_messages: inferred_capability_status(adapter_module, :fetch_messages),
      fetch_channel_messages: inferred_capability_status(adapter_module, :fetch_channel_messages),
      list_threads: inferred_capability_status(adapter_module, :list_threads),
      open_thread: inferred_capability_status(adapter_module, :open_thread),
      post_channel_message: inferred_capability_status(adapter_module, :post_channel_message),
      stream: inferred_capability_status(adapter_module, :stream),
      open_modal: inferred_capability_status(adapter_module, :open_modal),
      webhook: inferred_capability_status(adapter_module, :webhook),
      verify_webhook: inferred_capability_status(adapter_module, :verify_webhook),
      parse_event: inferred_capability_status(adapter_module, :parse_event),
      format_webhook_response: inferred_capability_status(adapter_module, :format_webhook_response)
    }

    matrix =
      defaults
      |> Map.merge(matrix)
      |> Map.put(:send_message, :native)
      |> canonicalize_core_fallback_capabilities(adapter_module)

    single_upload_supported? =
      supported_status?(matrix[:send_file]) or matrix[:post_message] == :native

    multi_upload_supported? =
      supported_status?(matrix[:multi_file]) or matrix[:post_message] == :native

    presentation_defaults = %{
      text: :native,
      image: if(single_upload_supported?, do: :fallback, else: :unsupported),
      audio: if(single_upload_supported?, do: :fallback, else: :unsupported),
      video: if(single_upload_supported?, do: :fallback, else: :unsupported),
      file: if(single_upload_supported?, do: :fallback, else: :unsupported),
      multi_file: if(multi_upload_supported?, do: :fallback, else: :unsupported),
      markdown: :unsupported,
      cards: :unsupported,
      modals: support_status(adapter_module, :open_modal, 3),
      ephemeral:
        cond do
          callback_exported?(adapter_module, :post_ephemeral, 4) -> :native
          callback_exported?(adapter_module, :open_dm, 2) -> :fallback
          true -> :unsupported
        end,
      assistant_events: :unsupported
    }

    Map.merge(presentation_defaults, matrix)
  end

  defp canonicalize_core_fallback_capabilities(matrix, adapter_module) do
    Enum.reduce(@core_fallback_capabilities, matrix, fn capability, acc ->
      inferred_status = inferred_capability_status(adapter_module, capability)

      case {Map.fetch!(acc, capability), inferred_status} do
        {:unsupported, status} -> Map.put(acc, capability, status)
        {:fallback, :native} -> Map.put(acc, capability, :native)
        _other -> acc
      end
    end)
  end

  defp normalize_webhook_request(%WebhookRequest{} = request, _opts), do: request

  defp normalize_webhook_request(request, opts) when is_map(request) do
    adapter_name = opts[:adapter_name]

    request
    |> Map.put_new(:adapter_name, adapter_name)
    |> WebhookRequest.new()
  end

  defp normalize_webhook_request(other, _opts), do: WebhookRequest.new(%{payload: %{raw: other}})

  defp normalize_post_payload_input(%PostPayload{} = payload), do: {:ok, payload}

  defp normalize_post_payload_input(%Postable{} = postable),
    do: {:ok, Postable.to_payload(postable)}

  defp normalize_post_payload_input(input) when is_binary(input),
    do: {:ok, PostPayload.text(input)}

  defp normalize_post_payload_input(input) when is_map(input) do
    try do
      {:ok, input |> Postable.new() |> Postable.to_payload()}
    rescue
      _ -> {:error, :invalid_postable}
    end
  end

  defp normalize_post_payload_input(_input), do: {:error, :invalid_postable}

  defp metadata_from_opts(opts) when is_list(opts) do
    case Keyword.get(opts, :metadata) do
      metadata when is_map(metadata) -> metadata
      _other -> %{}
    end
  end

  defp normalize_event_envelope(_adapter_module, %EventEnvelope{} = envelope), do: envelope

  defp normalize_event_envelope(adapter_module, map) when is_map(map) do
    map
    |> Map.put_new(:adapter_name, adapter_type(adapter_module))
    |> EventEnvelope.new()
  end

  defp normalize_webhook_response(%WebhookResponse{} = response), do: response
  defp normalize_webhook_response(map) when is_map(map), do: WebhookResponse.new(map)

  defp default_webhook_response({:ok, _chat, _event}),
    do: WebhookResponse.accepted(%{ok: true})

  defp default_webhook_response({:error, {:invalid_webhook_secret, _}}),
    do: WebhookResponse.error(401, %{error: "invalid_webhook_secret"})

  defp default_webhook_response({:error, :invalid_webhook_secret}),
    do: WebhookResponse.error(401, %{error: "invalid_webhook_secret"})

  defp default_webhook_response({:error, _reason}),
    do: WebhookResponse.error(400, %{error: "invalid_webhook_request"})

  defp default_webhook_response(_), do: WebhookResponse.accepted(%{ok: true})

  defp capability_callback(:initialize), do: {:initialize, 1}
  defp capability_callback(:shutdown), do: {:shutdown, 1}
  defp capability_callback(:send_message), do: {:send_message, 3}
  defp capability_callback(:send_file), do: {:send_file, 3}
  defp capability_callback(:post_message), do: {:post_message, 3}
  defp capability_callback(:edit_message), do: {:edit_message, 4}
  defp capability_callback(:delete_message), do: {:delete_message, 3}
  defp capability_callback(:start_typing), do: {:start_typing, 2}
  defp capability_callback(:fetch_metadata), do: {:fetch_metadata, 2}
  defp capability_callback(:fetch_thread), do: {:fetch_thread, 2}
  defp capability_callback(:fetch_message), do: {:fetch_message, 3}
  defp capability_callback(:get_user), do: {:get_user, 2}
  defp capability_callback(:fetch_subject), do: {:fetch_subject, 2}
  defp capability_callback(:get_thread_participants), do: {:get_thread_participants, 2}
  defp capability_callback(:mark_as_read), do: {:mark_as_read, 3}
  defp capability_callback(:fetch_media), do: {:fetch_media, 2}
  defp capability_callback(:add_reaction), do: {:add_reaction, 4}
  defp capability_callback(:remove_reaction), do: {:remove_reaction, 4}
  defp capability_callback(:post_ephemeral), do: {:post_ephemeral, 4}
  defp capability_callback(:open_dm), do: {:open_dm, 2}
  defp capability_callback(:fetch_messages), do: {:fetch_messages, 2}
  defp capability_callback(:fetch_channel_messages), do: {:fetch_channel_messages, 2}
  defp capability_callback(:list_threads), do: {:list_threads, 2}
  defp capability_callback(:open_thread), do: {:open_thread, 3}
  defp capability_callback(:post_channel_message), do: {:post_channel_message, 3}
  defp capability_callback(:stream), do: {:stream, 3}
  defp capability_callback(:open_modal), do: {:open_modal, 3}
  defp capability_callback(:webhook), do: {:handle_webhook, 3}
  defp capability_callback(:verify_webhook), do: {:verify_webhook, 2}
  defp capability_callback(:parse_event), do: {:parse_event, 2}
  defp capability_callback(:format_webhook_response), do: {:format_webhook_response, 2}
  defp capability_callback(_), do: nil

  defp callback_exported?(adapter_module, callback, arity) do
    Code.ensure_loaded?(adapter_module) and function_exported?(adapter_module, callback, arity)
  end

  defp subject_support_status(adapter_module) do
    cond do
      callback_exported?(adapter_module, :fetch_subject, 2) -> :native
      callback_exported?(adapter_module, :fetch_thread, 2) -> :fallback
      true -> :unsupported
    end
  end

  defp maybe_put_caption(opts, %PostPayload{} = payload) do
    case PostPayload.display_text(payload) do
      nil ->
        opts

      "" ->
        opts

      text ->
        opts
        |> Keyword.put_new(:caption, text)
        |> Keyword.put_new(:text, text)
    end
  end

  defp maybe_put_metadata(opts, metadata) when metadata in [%{}, nil], do: opts

  defp maybe_put_metadata(opts, metadata) when is_map(metadata) do
    Keyword.update(opts, :metadata, metadata, &Map.merge(metadata, &1))
  end

  defp stringify(nil), do: nil
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: to_string(value)
end
