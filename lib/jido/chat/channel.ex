defmodule Jido.Chat.Channel do
  @moduledoc """
  Behaviour contract for messaging channel implementations.

  Channel implementations must provide v1 callbacks for inbound normalization
  and outbound text delivery. v2 expands the contract with optional callbacks
  for lifecycle, routing metadata, security hooks, media operations, and
  command hints.

  v2 callbacks are optional and every helper in this module has deterministic
  defaults so v1-only channels remain fully compatible.

  ## v1 callbacks (required)

    * `channel_type/0`
    * `transform_incoming/1`
    * `send_message/3`

  ## v2 callbacks (optional)

    * `listener_child_specs/2`
    * `extract_routing_metadata/1`
    * `verify_sender/2`
    * `sanitize_outbound/2`
    * `send_media/3`
    * `edit_media/4`
    * `extract_command_hint/1`
    * `edit_message/4`

  ## Failure classes

  Callback failures are normalized into explicit classes:

    * `:recoverable` - transient, retry-safe failure
    * `:fatal` - non-recoverable failure that should crash/escalate
    * `:degraded` - unsupported or policy-denied path; continue degraded

  Use `failure_disposition/1` to map failure classes to runtime action
  (`:retry`, `:crash`, `:degrade`).
  """

  @v1_capabilities [
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

  @v2_capability_callbacks %{
    listener_lifecycle: {:listener_child_specs, 2},
    routing_metadata: {:extract_routing_metadata, 1},
    sender_verification: {:verify_sender, 2},
    outbound_sanitization: {:sanitize_outbound, 2},
    media_send: {:send_media, 3},
    media_edit: {:edit_media, 4},
    command_hints: {:extract_command_hint, 1},
    message_edit: {:edit_message, 4}
  }

  @all_capabilities @v1_capabilities ++ Map.keys(@v2_capability_callbacks)

  @type raw_payload :: map()
  @type external_room_id :: String.t() | integer()
  @type external_user_id :: String.t() | integer()
  @type external_message_id :: String.t() | integer()

  @type incoming_message :: %{
          required(:external_room_id) => external_room_id(),
          required(:external_user_id) => external_user_id(),
          required(:text) => String.t() | nil,
          optional(:username) => String.t() | nil,
          optional(:display_name) => String.t() | nil,
          optional(:external_message_id) => external_message_id(),
          optional(:external_reply_to_id) => external_message_id() | nil,
          optional(:external_thread_id) => String.t() | nil,
          optional(:timestamp) => integer() | nil,
          optional(:chat_type) => atom(),
          optional(:chat_title) => String.t() | nil,
          optional(:was_mentioned) => boolean(),
          optional(:mentions) => [map()],
          optional(:media) => [map()],
          optional(:channel_meta) => map(),
          optional(:raw) => map()
        }

  @type send_result :: {:ok, map()} | {:error, term()}

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

  @type callback_name ::
          :listener_child_specs
          | :extract_routing_metadata
          | :verify_sender
          | :sanitize_outbound
          | :send_media
          | :edit_media
          | :extract_command_hint
          | :edit_message

  @type failure_class :: :recoverable | :fatal | :degraded
  @type failure_disposition :: :retry | :crash | :degrade

  @type callback_failure :: %{
          required(:type) => :channel_callback_failure,
          required(:channel) => module(),
          required(:callback) => callback_name(),
          required(:class) => failure_class(),
          required(:disposition) => failure_disposition(),
          required(:reason) => term(),
          optional(:kind) => :error | :throw | :exit,
          optional(:stacktrace) => [term()]
        }

  @type contract_failure :: %{
          required(:type) => :channel_contract_failure,
          required(:channel) => module(),
          required(:capability) => atom(),
          required(:callback) => callback_name() | :capabilities,
          required(:class) => :fatal,
          required(:disposition) => :crash,
          required(:reason) => :missing_callback | :unknown_capability
        }

  @doc "Returns the channel type atom (for example `:telegram`, `:discord`)"
  @callback channel_type() :: atom()

  @doc """
  Returns the list of capabilities this channel supports.

  Defaults to `[:text]` when not implemented.
  """
  @callback capabilities() :: [capability()]

  @doc """
  Transform a raw incoming payload into a normalized message map.

  Returns `{:ok, incoming_message}` or `{:error, reason}`.
  """
  @callback transform_incoming(raw_payload()) ::
              {:ok, incoming_message()} | {:error, term()}

  @doc """
  Send a text message to an external room.

  Options may include platform-specific settings like parse mode or reply target.
  """
  @callback send_message(external_room_id(), text :: String.t(), opts :: keyword()) ::
              send_result()

  @doc """
  Optional lifecycle hook returning listener/poller child specs.

  Defaults to `{:ok, []}`.
  """
  @callback listener_child_specs(instance_id :: String.t(), opts :: keyword()) ::
              {:ok, [Supervisor.child_spec()]} | {:error, term()}

  @doc """
  Optional hook to extract routing metadata from a raw payload.

  Defaults to `{:ok, %{}}`.
  """
  @callback extract_routing_metadata(raw_payload()) :: {:ok, map()} | {:error, term()}

  @doc """
  Optional sender verification hook.

  Defaults to `:ok`.
  """
  @callback verify_sender(incoming_message(), raw_payload()) ::
              :ok | {:ok, map()} | {:error, term()}

  @doc """
  Optional outbound sanitize hook.

  Defaults to `{:ok, outbound}` (no-op).
  """
  @callback sanitize_outbound(outbound :: term(), opts :: keyword()) ::
              {:ok, term()} | {:error, term()}

  @doc """
  Optional outbound media send callback.

  Defaults to `{:error, :unsupported}`.
  """
  @callback send_media(external_room_id(), media_payload :: map(), opts :: keyword()) ::
              send_result()

  @doc """
  Optional outbound media edit callback.

  Defaults to `{:error, :unsupported}`.
  """
  @callback edit_media(
              external_room_id(),
              external_message_id(),
              media_payload :: map(),
              opts :: keyword()
            ) :: send_result()

  @doc """
  Optional command hint extraction callback.

  Defaults to `{:ok, nil}`.
  """
  @callback extract_command_hint(incoming_message()) :: {:ok, map() | nil} | {:error, term()}

  @doc """
  Optional text message edit callback used by streaming updates.

  Defaults to `{:error, :unsupported}`.
  """
  @callback edit_message(
              external_room_id(),
              external_message_id(),
              text :: String.t(),
              opts :: keyword()
            ) :: send_result()

  @optional_callbacks capabilities: 0,
                      listener_child_specs: 2,
                      extract_routing_metadata: 1,
                      verify_sender: 2,
                      sanitize_outbound: 2,
                      send_media: 3,
                      edit_media: 4,
                      extract_command_hint: 1,
                      edit_message: 4

  defmacro __using__(_opts) do
    quote do
      @behaviour Jido.Chat.Channel
      @after_compile {Jido.Chat.Channel, :__after_compile__}
    end
  end

  @doc false
  @spec __after_compile__(Macro.Env.t(), binary()) :: :ok
  def __after_compile__(%Macro.Env{} = env, _bytecode) do
    case validate_capability_contract(env.module) do
      :ok ->
        :ok

      {:error, failures} ->
        formatted = Enum.map_join(failures, "\n", &format_contract_failure/1)

        raise CompileError,
          file: env.file,
          line: env.line,
          description:
            "channel capability contract failed for #{inspect(env.module)}:\n" <> formatted
    end
  end

  @doc "Returns channel capabilities with `[:text]` fallback."
  @spec capabilities(module()) :: [capability()]
  def capabilities(channel_module) when is_atom(channel_module) do
    Code.ensure_loaded(channel_module)

    if function_exported?(channel_module, :capabilities, 0) do
      channel_module.capabilities()
    else
      [:text]
    end
  end

  @doc """
  Validates that declared capabilities are known and backed by required callbacks.

  Returns `:ok` when aligned, otherwise `{:error, [contract_failure]}`.
  """
  @spec validate_capability_contract(module()) :: :ok | {:error, [contract_failure()]}
  def validate_capability_contract(channel_module) when is_atom(channel_module) do
    Code.ensure_loaded(channel_module)

    failures =
      channel_module
      |> capabilities()
      |> Enum.uniq()
      |> Enum.flat_map(&capability_failures(channel_module, &1))

    if failures == [], do: :ok, else: {:error, failures}
  end

  @doc """
  Returns deterministic listener child specs for a channel.

  Defaults to `{:ok, []}` when callback is not implemented.
  """
  @spec listener_child_specs(module(), String.t(), keyword()) ::
          {:ok, [Supervisor.child_spec()]} | {:error, callback_failure()}
  def listener_child_specs(channel_module, instance_id, opts \\ [])
      when is_atom(channel_module) and is_binary(instance_id) and is_list(opts) do
    invoke_optional(
      channel_module,
      :listener_child_specs,
      [instance_id, opts],
      {:ok, []},
      fn result ->
        case result do
          {:ok, child_specs} when is_list(child_specs) ->
            {:ok, child_specs}

          {:error, reason} ->
            {:error, callback_failure(channel_module, :listener_child_specs, reason)}

          other ->
            {:error,
             callback_failure(channel_module, :listener_child_specs, {:invalid_return, other})}
        end
      end
    )
  end

  @doc """
  Returns deterministic routing metadata for a channel payload.

  Defaults to `{:ok, %{}}` when callback is not implemented.
  """
  @spec extract_routing_metadata(module(), raw_payload()) ::
          {:ok, map()} | {:error, callback_failure()}
  def extract_routing_metadata(channel_module, raw_payload)
      when is_atom(channel_module) and is_map(raw_payload) do
    invoke_optional(
      channel_module,
      :extract_routing_metadata,
      [raw_payload],
      {:ok, %{}},
      fn result ->
        case result do
          {:ok, metadata} when is_map(metadata) ->
            {:ok, metadata}

          {:error, reason} ->
            {:error, callback_failure(channel_module, :extract_routing_metadata, reason)}

          other ->
            {:error,
             callback_failure(channel_module, :extract_routing_metadata, {:invalid_return, other})}
        end
      end
    )
  end

  @doc """
  Runs sender verification for a channel.

  Defaults to `:ok` when callback is not implemented.
  """
  @spec verify_sender(module(), incoming_message(), raw_payload()) ::
          :ok | {:ok, map()} | {:error, callback_failure()}
  def verify_sender(channel_module, incoming_message, raw_payload)
      when is_atom(channel_module) and is_map(incoming_message) and is_map(raw_payload) do
    invoke_optional(
      channel_module,
      :verify_sender,
      [incoming_message, raw_payload],
      :ok,
      fn result ->
        case result do
          :ok ->
            :ok

          {:ok, metadata} when is_map(metadata) ->
            {:ok, metadata}

          {:error, reason} ->
            {:error, callback_failure(channel_module, :verify_sender, reason)}

          other ->
            {:error, callback_failure(channel_module, :verify_sender, {:invalid_return, other})}
        end
      end
    )
  end

  @doc """
  Runs outbound sanitization for a channel.

  Defaults to `{:ok, outbound}` when callback is not implemented.
  """
  @spec sanitize_outbound(module(), term(), keyword()) ::
          {:ok, term()} | {:error, callback_failure()}
  def sanitize_outbound(channel_module, outbound, opts \\ [])
      when is_atom(channel_module) and is_list(opts) do
    invoke_optional(
      channel_module,
      :sanitize_outbound,
      [outbound, opts],
      {:ok, outbound},
      fn result ->
        case result do
          {:ok, sanitized} ->
            {:ok, sanitized}

          {:error, reason} ->
            {:error, callback_failure(channel_module, :sanitize_outbound, reason)}

          other ->
            {:error,
             callback_failure(channel_module, :sanitize_outbound, {:invalid_return, other})}
        end
      end
    )
  end

  @doc """
  Sends media through a channel if supported.

  Defaults to a typed `:unsupported` failure when callback is not implemented.
  """
  @spec send_media(module(), external_room_id(), map(), keyword()) ::
          {:ok, map()} | {:error, callback_failure()}
  def send_media(channel_module, external_room_id, media_payload, opts \\ [])
      when is_atom(channel_module) and is_map(media_payload) and is_list(opts) do
    default = {:error, callback_failure(channel_module, :send_media, :unsupported)}

    invoke_optional(
      channel_module,
      :send_media,
      [external_room_id, media_payload, opts],
      default,
      fn
        {:ok, result} when is_map(result) ->
          {:ok, result}

        {:error, reason} ->
          {:error, callback_failure(channel_module, :send_media, reason)}

        other ->
          {:error, callback_failure(channel_module, :send_media, {:invalid_return, other})}
      end
    )
  end

  @doc """
  Edits media through a channel if supported.

  Defaults to a typed `:unsupported` failure when callback is not implemented.
  """
  @spec edit_media(module(), external_room_id(), external_message_id(), map(), keyword()) ::
          {:ok, map()} | {:error, callback_failure()}
  def edit_media(channel_module, external_room_id, external_message_id, media_payload, opts \\ [])
      when is_atom(channel_module) and is_map(media_payload) and is_list(opts) do
    default = {:error, callback_failure(channel_module, :edit_media, :unsupported)}

    invoke_optional(
      channel_module,
      :edit_media,
      [external_room_id, external_message_id, media_payload, opts],
      default,
      fn
        {:ok, result} when is_map(result) ->
          {:ok, result}

        {:error, reason} ->
          {:error, callback_failure(channel_module, :edit_media, reason)}

        other ->
          {:error, callback_failure(channel_module, :edit_media, {:invalid_return, other})}
      end
    )
  end

  @doc """
  Extracts command hints from an incoming message when supported.

  Defaults to `{:ok, nil}` when callback is not implemented.
  """
  @spec extract_command_hint(module(), incoming_message()) ::
          {:ok, map() | nil} | {:error, callback_failure()}
  def extract_command_hint(channel_module, incoming_message)
      when is_atom(channel_module) and is_map(incoming_message) do
    invoke_optional(
      channel_module,
      :extract_command_hint,
      [incoming_message],
      {:ok, nil},
      fn result ->
        case result do
          {:ok, nil} ->
            {:ok, nil}

          {:ok, hint} when is_map(hint) ->
            {:ok, hint}

          {:error, reason} ->
            {:error, callback_failure(channel_module, :extract_command_hint, reason)}

          other ->
            {:error,
             callback_failure(channel_module, :extract_command_hint, {:invalid_return, other})}
        end
      end
    )
  end

  @doc """
  Edits text through a channel if supported.

  Defaults to a typed `:unsupported` failure when callback is not implemented.
  """
  @spec edit_message(module(), external_room_id(), external_message_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, callback_failure()}
  def edit_message(channel_module, external_room_id, external_message_id, text, opts \\ [])
      when is_atom(channel_module) and is_binary(text) and is_list(opts) do
    default = {:error, callback_failure(channel_module, :edit_message, :unsupported)}

    invoke_optional(
      channel_module,
      :edit_message,
      [external_room_id, external_message_id, text, opts],
      default,
      fn
        {:ok, result} when is_map(result) ->
          {:ok, result}

        {:error, reason} ->
          {:error, callback_failure(channel_module, :edit_message, reason)}

        other ->
          {:error, callback_failure(channel_module, :edit_message, {:invalid_return, other})}
      end
    )
  end

  @doc "Returns the runtime disposition for a failure class or callback failure envelope."
  @spec failure_disposition(failure_class() | callback_failure()) :: failure_disposition()
  def failure_disposition(:recoverable), do: :retry
  def failure_disposition(:fatal), do: :crash
  def failure_disposition(:degraded), do: :degrade

  def failure_disposition(%{disposition: disposition}) do
    disposition
  end

  @doc "Classifies callback failure reasons into `:recoverable`, `:fatal`, or `:degraded`."
  @spec classify_failure(term()) :: failure_class()
  def classify_failure(%{class: class}) when class in [:recoverable, :fatal, :degraded], do: class

  def classify_failure({class, _reason}) when class in [:recoverable, :fatal, :degraded],
    do: class

  def classify_failure(reason)
      when reason in [
             :unsupported,
             :not_supported,
             :not_implemented,
             :denied,
             :unauthorized_sender,
             :forbidden_sender
           ],
      do: :degraded

  def classify_failure({tag, _})
      when tag in [
             :unsupported,
             :not_supported,
             :not_implemented,
             :denied,
             :unauthorized_sender,
             :forbidden_sender
           ],
      do: :degraded

  def classify_failure(reason)
      when reason in [
             :timeout,
             :rate_limited,
             :temporary_unavailable,
             :disconnected,
             :network_error
           ],
      do: :recoverable

  def classify_failure({tag, _})
      when tag in [:timeout, :rate_limited, :temporary_unavailable, :disconnected, :network_error],
      do: :recoverable

  def classify_failure(reason)
      when reason in [
             :invalid_configuration,
             :invalid_credentials,
             :invalid_callback,
             :invalid_return,
             :misconfigured,
             :unauthorized,
             :forbidden
           ],
      do: :fatal

  def classify_failure({tag, _})
      when tag in [
             :invalid_configuration,
             :invalid_credentials,
             :invalid_callback,
             :invalid_return,
             :misconfigured,
             :unauthorized,
             :forbidden,
             :invalid_return
           ],
      do: :fatal

  def classify_failure({:exception, _exception}), do: :fatal
  def classify_failure(_reason), do: :recoverable

  @doc "Returns all capability atoms recognized by the channel contract."
  @spec all_capabilities() :: [capability()]
  def all_capabilities, do: @all_capabilities

  defp invoke_optional(channel_module, callback, args, default, handler) do
    if function_exported?(channel_module, callback, length(args)) do
      try do
        channel_module
        |> apply(callback, args)
        |> handler.()
      rescue
        exception ->
          {:error,
           callback_failure(
             channel_module,
             callback,
             {:exception, exception},
             :error,
             __STACKTRACE__
           )}
      catch
        kind, reason ->
          {:error, callback_failure(channel_module, callback, reason, kind, __STACKTRACE__)}
      end
    else
      default
    end
  end

  defp callback_failure(channel_module, callback, reason, kind \\ nil, stacktrace \\ nil) do
    class = classify_failure(reason)

    failure = %{
      type: :channel_callback_failure,
      channel: channel_module,
      callback: callback,
      class: class,
      disposition: failure_disposition(class),
      reason: reason
    }

    failure
    |> maybe_put(:kind, kind)
    |> maybe_put(:stacktrace, stacktrace)
  end

  defp contract_failure(channel_module, capability, callback, reason) do
    %{
      type: :channel_contract_failure,
      channel: channel_module,
      capability: capability,
      callback: callback,
      class: :fatal,
      disposition: :crash,
      reason: reason
    }
  end

  defp capability_failures(channel_module, capability) do
    cond do
      capability in @v1_capabilities ->
        []

      match?({_, _}, Map.get(@v2_capability_callbacks, capability)) ->
        {callback, arity} = Map.fetch!(@v2_capability_callbacks, capability)

        if function_exported?(channel_module, callback, arity) do
          []
        else
          [contract_failure(channel_module, capability, callback, :missing_callback)]
        end

      true ->
        [contract_failure(channel_module, capability, :capabilities, :unknown_capability)]
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp format_contract_failure(%{
         capability: capability,
         callback: callback,
         reason: :missing_callback
       }) do
    "- capability #{inspect(capability)} requires callback #{callback}/#{required_arity(capability)}"
  end

  defp format_contract_failure(%{capability: capability, reason: :unknown_capability}) do
    "- capability #{inspect(capability)} is not recognized by Jido.Chat.Channel"
  end

  defp required_arity(capability) do
    case Map.get(@v2_capability_callbacks, capability) do
      {_callback, arity} -> arity
      _ -> 0
    end
  end
end
