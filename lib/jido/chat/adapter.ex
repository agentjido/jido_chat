defmodule Jido.Chat.Adapter do
  @moduledoc """
  Canonical adapter behavior for Chat SDK style integrations.

  `Jido.Chat.Channel` remains available as a compatibility behavior during migration.
  """

  alias Jido.Chat.{
    CapabilityMatrix,
    ChannelInfo,
    EventEnvelope,
    EphemeralMessage,
    FetchOptions,
    Incoming,
    ModalResult,
    Message,
    MessagePage,
    Response,
    WebhookRequest,
    WebhookResponse,
    Thread,
    ThreadPage
  }

  @type raw_payload :: map()
  @type external_room_id :: String.t() | integer()
  @type external_user_id :: String.t() | integer()
  @type external_message_id :: String.t() | integer()
  @type sink_mfa :: {module(), atom(), [term()]}
  @type listener_opts :: keyword()

  @type capability_status :: :native | :fallback | :unsupported
  @type capability_matrix :: %{optional(atom()) => capability_status()}

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

  @callback channel_type() :: atom()
  @callback transform_incoming(raw_payload()) :: incoming_result() | {:ok, map()}

  @callback send_message(external_room_id(), text :: String.t(), opts :: keyword()) ::
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
                      edit_message: 4,
                      delete_message: 3,
                      start_typing: 2,
                      fetch_metadata: 2,
                      fetch_thread: 2,
                      fetch_message: 3,
                      add_reaction: 4,
                      remove_reaction: 4,
                      post_ephemeral: 4,
                      post_channel_message: 3,
                      stream: 3,
                      open_modal: 3,
                      fetch_messages: 2,
                      fetch_channel_messages: 2,
                      list_threads: 2,
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
    if function_exported?(adapter_module, :initialize, 1) do
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
    if function_exported?(adapter_module, :shutdown, 1) do
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
    if function_exported?(adapter_module, :capabilities, 0) do
      adapter_module.capabilities()
      |> normalize_capability_matrix()
      |> ensure_capability_defaults(adapter_module)
    else
      %{
        initialize: support_status(adapter_module, :initialize, 1, :fallback),
        shutdown: support_status(adapter_module, :shutdown, 1, :fallback),
        send_message: :native,
        edit_message: support_status(adapter_module, :edit_message, 4),
        delete_message: support_status(adapter_module, :delete_message, 3),
        start_typing: support_status(adapter_module, :start_typing, 2),
        fetch_metadata: support_status(adapter_module, :fetch_metadata, 2, :fallback),
        fetch_thread: support_status(adapter_module, :fetch_thread, 2, :fallback),
        fetch_message: support_status(adapter_module, :fetch_message, 3, :fallback),
        add_reaction: support_status(adapter_module, :add_reaction, 4),
        remove_reaction: support_status(adapter_module, :remove_reaction, 4),
        post_ephemeral: support_status(adapter_module, :post_ephemeral, 4),
        open_dm: support_status(adapter_module, :open_dm, 2),
        fetch_messages: support_status(adapter_module, :fetch_messages, 2),
        fetch_channel_messages: support_status(adapter_module, :fetch_channel_messages, 2),
        list_threads: support_status(adapter_module, :list_threads, 2),
        post_channel_message: support_status(adapter_module, :post_channel_message, 3, :fallback),
        stream: support_status(adapter_module, :stream, 3, :fallback),
        open_modal: support_status(adapter_module, :open_modal, 3),
        webhook: support_status(adapter_module, :handle_webhook, 3, :fallback),
        verify_webhook: support_status(adapter_module, :verify_webhook, 2, :fallback),
        parse_event: support_status(adapter_module, :parse_event, 2, :fallback),
        format_webhook_response:
          support_status(adapter_module, :format_webhook_response, 2, :fallback)
      }
    end
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

  @doc "Posts a channel-level message using adapter callback or send fallback."
  @spec post_channel_message(module(), external_room_id(), String.t(), keyword()) :: send_result()
  def post_channel_message(adapter_module, external_room_id, text, opts \\ []) do
    if function_exported?(adapter_module, :post_channel_message, 3) do
      with {:ok, response} <- adapter_module.post_channel_message(external_room_id, text, opts) do
        {:ok, normalize_response(adapter_module, response)}
      end
    else
      send_message(adapter_module, external_room_id, text, opts)
    end
  end

  @doc "Streams chunked text using adapter stream callback or send fallback."
  @spec stream(module(), external_room_id(), Enumerable.t(), keyword()) :: send_result()
  def stream(adapter_module, external_room_id, chunks, opts \\ []) do
    if function_exported?(adapter_module, :stream, 3) do
      with {:ok, response} <- adapter_module.stream(external_room_id, chunks, opts) do
        {:ok, normalize_response(adapter_module, response)}
      end
    else
      text = chunks |> Enum.map(&to_string/1) |> Enum.join("")
      send_message(adapter_module, external_room_id, text, opts)
    end
  end

  @doc "Normalizes adapter edit results to `Jido.Chat.Response`."
  @spec edit_message(module(), external_room_id(), external_message_id(), String.t(), keyword()) ::
          send_result()
  def edit_message(adapter_module, external_room_id, external_message_id, text, opts \\ []) do
    if function_exported?(adapter_module, :edit_message, 4) do
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
    if function_exported?(adapter_module, :delete_message, 3) do
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
    if function_exported?(adapter_module, :start_typing, 2) do
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
    if function_exported?(adapter_module, :fetch_metadata, 2) do
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
    if function_exported?(adapter_module, :fetch_thread, 2) do
      with {:ok, thread} <- adapter_module.fetch_thread(external_room_id, opts) do
        {:ok, normalize_thread(adapter_module, thread, external_room_id, opts)}
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
    if function_exported?(adapter_module, :fetch_message, 3) do
      with {:ok, message} <-
             adapter_module.fetch_message(external_room_id, external_message_id, opts) do
        {:ok, normalize_message(adapter_module, message, opts)}
      end
    else
      {:error, :unsupported}
    end
  end

  @doc "Adds a reaction when supported by adapter."
  @spec add_reaction(module(), external_room_id(), external_message_id(), String.t(), keyword()) ::
          reaction_result()
  def add_reaction(adapter_module, external_room_id, external_message_id, emoji, opts \\ []) do
    if function_exported?(adapter_module, :add_reaction, 4) do
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
    if function_exported?(adapter_module, :remove_reaction, 4) do
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
    if function_exported?(adapter_module, :post_ephemeral, 4) do
      with {:ok, message} <-
             adapter_module.post_ephemeral(external_room_id, external_user_id, text, opts) do
        {:ok, normalize_ephemeral(adapter_module, message, external_room_id, false)}
      end
    else
      fallback_to_dm = Keyword.get(opts, :fallback_to_dm, false)

      if fallback_to_dm and function_exported?(adapter_module, :open_dm, 2) do
        with {:ok, dm_room_id} <- adapter_module.open_dm(external_user_id, opts),
             {:ok, response} <- send_message(adapter_module, dm_room_id, text, opts) do
          {:ok,
           EphemeralMessage.new(%{
             id: response.external_message_id || Jido.Chat.ID.generate!(),
             thread_id: fallback_thread_id(adapter_module, dm_room_id),
             used_fallback: true,
             raw: response.raw,
             metadata: %{source_room_id: external_room_id}
           })}
        end
      else
        {:error, :unsupported}
      end
    end
  end

  @doc "Opens adapter-native modal when supported."
  @spec open_modal(module(), external_room_id(), map(), keyword()) ::
          modal_result()
  def open_modal(adapter_module, external_room_id, payload, opts \\ []) when is_map(payload) do
    if function_exported?(adapter_module, :open_modal, 3) do
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
    if function_exported?(adapter_module, :fetch_messages, 2) do
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
    if function_exported?(adapter_module, :fetch_channel_messages, 2) do
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
    if function_exported?(adapter_module, :list_threads, 2) do
      with {:ok, page} <- adapter_module.list_threads(external_room_id, opts) do
        {:ok, normalize_thread_page(page)}
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

    if function_exported?(adapter_module, :verify_webhook, 2) do
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
      function_exported?(adapter_module, :parse_event, 2) ->
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
    if function_exported?(adapter_module, :format_webhook_response, 2) do
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
    declared = capabilities(adapter_module)

    invalid =
      Enum.reduce(declared, [], fn {capability, status}, acc ->
        callback = capability_callback(capability)

        case callback do
          nil ->
            acc

          {name, arity} ->
            exported? = function_exported?(adapter_module, name, arity)

            case {status, exported?} do
              {:native, false} -> [{capability, :missing_callback} | acc]
              _ -> acc
            end
        end
      end)

    case invalid do
      [] -> :ok
      _ -> {:error, {:invalid_capability_matrix, Enum.reverse(invalid)}}
    end
  end

  @doc "Returns adapter channel type with fallback to module name."
  @spec adapter_type(module()) :: atom()
  def adapter_type(adapter_module) do
    if function_exported?(adapter_module, :channel_type, 0) do
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
    if function_exported?(adapter_module, callback, arity), do: :native, else: fallback
  end

  defp normalize_capability_matrix(matrix) when is_map(matrix),
    do: matrix |> then(&CapabilityMatrix.new(%{capabilities: &1})) |> CapabilityMatrix.as_map()

  defp normalize_capability_matrix(_), do: %{}

  defp normalize_incoming(%Incoming{} = incoming), do: incoming
  defp normalize_incoming(map) when is_map(map), do: Incoming.new(map)

  defp normalize_response(adapter_module, %Response{} = response) do
    response
    |> Map.put_new(:channel_type, adapter_type(adapter_module))
    |> Response.new()
  end

  defp normalize_response(adapter_module, map) when is_map(map) do
    map
    |> Map.put_new(:channel_type, adapter_type(adapter_module))
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
    Thread.new(%{
      id: thread[:id] || thread["id"] || "#{adapter_type(adapter_module)}:#{external_room_id}",
      adapter_name:
        thread[:adapter_name] || thread["adapter_name"] || adapter_type(adapter_module),
      adapter: thread[:adapter] || thread["adapter"] || adapter_module,
      external_room_id:
        thread[:external_room_id] || thread["external_room_id"] || external_room_id,
      external_thread_id:
        thread[:external_thread_id] || thread["external_thread_id"] || opts[:external_thread_id],
      channel_id: thread[:channel_id] || thread["channel_id"],
      is_dm: thread[:is_dm] || thread["is_dm"] || false,
      metadata: thread[:metadata] || thread["metadata"] || %{}
    })
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

  defp normalize_ephemeral(
         _adapter_module,
         %EphemeralMessage{} = message,
         _external_room_id,
         _used_fallback
       ),
       do: message

  defp normalize_ephemeral(adapter_module, message, external_room_id, used_fallback)
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
      used_fallback: message[:used_fallback] || message["used_fallback"] || used_fallback,
      raw: message[:raw] || message["raw"],
      metadata: message[:metadata] || message["metadata"] || %{}
    })
  end

  defp normalize_modal_result(%ModalResult{} = result, _external_room_id), do: result

  defp normalize_modal_result(result, external_room_id) when is_map(result) do
    ModalResult.new(%{
      id: result[:id] || result["id"] || Jido.Chat.ID.generate!(),
      status: result[:status] || result["status"] || :opened,
      external_room_id:
        result[:external_room_id] || result["external_room_id"] || external_room_id,
      external_message_id:
        stringify(result[:external_message_id] || result["external_message_id"]),
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

  defp default_channel_info(adapter_module, external_room_id) do
    ChannelInfo.new(%{
      id: to_string(external_room_id),
      metadata: %{adapter_name: adapter_type(adapter_module)}
    })
  end

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

  defp ensure_capability_defaults(matrix, adapter_module) do
    defaults = %{
      initialize: support_status(adapter_module, :initialize, 1, :fallback),
      shutdown: support_status(adapter_module, :shutdown, 1, :fallback),
      send_message: :native,
      edit_message: support_status(adapter_module, :edit_message, 4),
      delete_message: support_status(adapter_module, :delete_message, 3),
      start_typing: support_status(adapter_module, :start_typing, 2),
      fetch_metadata: support_status(adapter_module, :fetch_metadata, 2, :fallback),
      fetch_thread: support_status(adapter_module, :fetch_thread, 2, :fallback),
      fetch_message: support_status(adapter_module, :fetch_message, 3, :fallback),
      add_reaction: support_status(adapter_module, :add_reaction, 4),
      remove_reaction: support_status(adapter_module, :remove_reaction, 4),
      post_ephemeral: support_status(adapter_module, :post_ephemeral, 4),
      open_dm: support_status(adapter_module, :open_dm, 2),
      fetch_messages: support_status(adapter_module, :fetch_messages, 2),
      fetch_channel_messages: support_status(adapter_module, :fetch_channel_messages, 2),
      list_threads: support_status(adapter_module, :list_threads, 2),
      post_channel_message: support_status(adapter_module, :post_channel_message, 3, :fallback),
      stream: support_status(adapter_module, :stream, 3, :fallback),
      open_modal: support_status(adapter_module, :open_modal, 3),
      webhook: support_status(adapter_module, :handle_webhook, 3, :fallback),
      verify_webhook: support_status(adapter_module, :verify_webhook, 2, :fallback),
      parse_event: support_status(adapter_module, :parse_event, 2, :fallback),
      format_webhook_response:
        support_status(adapter_module, :format_webhook_response, 2, :fallback)
    }

    Map.merge(defaults, matrix)
  end

  defp normalize_webhook_request(%WebhookRequest{} = request, _opts), do: request

  defp normalize_webhook_request(request, opts) when is_map(request) do
    adapter_name = opts[:adapter_name]

    request
    |> Map.put_new(:adapter_name, adapter_name)
    |> WebhookRequest.new()
  end

  defp normalize_webhook_request(other, _opts), do: WebhookRequest.new(%{payload: %{raw: other}})

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
  defp capability_callback(:edit_message), do: {:edit_message, 4}
  defp capability_callback(:delete_message), do: {:delete_message, 3}
  defp capability_callback(:start_typing), do: {:start_typing, 2}
  defp capability_callback(:fetch_metadata), do: {:fetch_metadata, 2}
  defp capability_callback(:fetch_thread), do: {:fetch_thread, 2}
  defp capability_callback(:fetch_message), do: {:fetch_message, 3}
  defp capability_callback(:add_reaction), do: {:add_reaction, 4}
  defp capability_callback(:remove_reaction), do: {:remove_reaction, 4}
  defp capability_callback(:post_ephemeral), do: {:post_ephemeral, 4}
  defp capability_callback(:open_dm), do: {:open_dm, 2}
  defp capability_callback(:fetch_messages), do: {:fetch_messages, 2}
  defp capability_callback(:fetch_channel_messages), do: {:fetch_channel_messages, 2}
  defp capability_callback(:list_threads), do: {:list_threads, 2}
  defp capability_callback(:post_channel_message), do: {:post_channel_message, 3}
  defp capability_callback(:stream), do: {:stream, 3}
  defp capability_callback(:open_modal), do: {:open_modal, 3}
  defp capability_callback(:webhook), do: {:handle_webhook, 3}
  defp capability_callback(:verify_webhook), do: {:verify_webhook, 2}
  defp capability_callback(:parse_event), do: {:parse_event, 2}
  defp capability_callback(:format_webhook_response), do: {:format_webhook_response, 2}
  defp capability_callback(_), do: nil

  defp stringify(nil), do: nil
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: to_string(value)
end
