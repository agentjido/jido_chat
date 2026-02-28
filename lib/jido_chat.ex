defmodule Jido.Chat do
  @moduledoc """
  Core chat SDK facade and event-loop state container.
  """

  alias Jido.Chat.{
    ActionEvent,
    Adapter,
    AdapterRegistry,
    AssistantContextChangedEvent,
    AssistantThreadStartedEvent,
    CapabilityMatrix,
    ChannelRef,
    EventRouter,
    EventEnvelope,
    Incoming,
    LegacyMessage,
    Message,
    ModalCloseEvent,
    ModalSubmitEvent,
    Participant,
    ReactionEvent,
    Room,
    Serialization,
    SlashCommandEvent,
    Thread,
    WebhookPipeline,
    WebhookRequest,
    WebhookResponse
  }

  alias Jido.Chat.Content.Text

  @typedoc "Mention handler callback."
  @type mention_handler ::
          (Thread.t(), Incoming.t() -> term()) | (t(), Thread.t(), Incoming.t() -> t() | term())
  @typedoc "Regex-routed message handler callback."
  @type message_handler :: mention_handler()
  @typedoc "Subscribed-thread handler callback."
  @type subscribed_handler :: mention_handler()

  @typedoc "Reaction event handler callback."
  @type reaction_handler ::
          (ReactionEvent.t() -> term()) | (t(), ReactionEvent.t() -> t() | term())
  @typedoc "Action event handler callback."
  @type action_handler :: (ActionEvent.t() -> term()) | (t(), ActionEvent.t() -> t() | term())

  @typedoc "Modal submit handler callback."
  @type modal_submit_handler ::
          (ModalSubmitEvent.t() -> term()) | (t(), ModalSubmitEvent.t() -> t() | term())

  @typedoc "Modal close handler callback."
  @type modal_close_handler ::
          (ModalCloseEvent.t() -> term()) | (t(), ModalCloseEvent.t() -> t() | term())

  @typedoc "Slash command handler callback."
  @type slash_command_handler ::
          (SlashCommandEvent.t() -> term()) | (t(), SlashCommandEvent.t() -> t() | term())

  @typedoc "Assistant thread started handler callback."
  @type assistant_thread_started_handler ::
          (AssistantThreadStartedEvent.t() -> term())
          | (t(), AssistantThreadStartedEvent.t() -> t() | term())

  @typedoc "Assistant context changed handler callback."
  @type assistant_context_changed_handler ::
          (AssistantContextChangedEvent.t() -> term())
          | (t(), AssistantContextChangedEvent.t() -> t() | term())

  @type handlers :: %{
          mention: [mention_handler()],
          message: [{Regex.t(), message_handler()}],
          subscribed: [subscribed_handler()],
          reaction: [reaction_handler()],
          action: [action_handler()],
          modal_submit: [modal_submit_handler()],
          modal_close: [modal_close_handler()],
          slash_command: [slash_command_handler()],
          assistant_thread_started: [assistant_thread_started_handler()],
          assistant_context_changed: [assistant_context_changed_handler()]
        }

  @type webhook_handler ::
          (t(), map(), keyword() -> {:ok, t(), Incoming.t()} | {:error, term()})

  @type webhook_request_handler ::
          (WebhookRequest.t() | map(), keyword() ->
             {:ok, t(), EventEnvelope.t() | nil, WebhookResponse.t()})

  @type webhook_request_handler_with_chat ::
          (t(), WebhookRequest.t() | map(), keyword() ->
             {:ok, t(), EventEnvelope.t() | nil, WebhookResponse.t()})

  @type t :: %__MODULE__{
          id: String.t(),
          user_name: String.t(),
          adapters: %{optional(atom()) => module()},
          subscriptions: MapSet.t(String.t()),
          dedupe: MapSet.t({atom(), String.t()}),
          handlers: handlers(),
          metadata: map(),
          thread_state: %{optional(String.t()) => map()},
          channel_state: %{optional(String.t()) => map()},
          initialized: boolean()
        }

  @default_handlers %{
    mention: [],
    message: [],
    subscribed: [],
    reaction: [],
    action: [],
    modal_submit: [],
    modal_close: [],
    slash_command: [],
    assistant_thread_started: [],
    assistant_context_changed: []
  }

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              user_name: Zoi.string() |> Zoi.default("bot"),
              adapters: Zoi.map() |> Zoi.default(%{}),
              subscriptions: Zoi.any() |> Zoi.default(MapSet.new()),
              dedupe: Zoi.any() |> Zoi.default(MapSet.new()),
              handlers: Zoi.map() |> Zoi.default(@default_handlers),
              metadata: Zoi.map() |> Zoi.default(%{}),
              thread_state: Zoi.map() |> Zoi.default(%{}),
              channel_state: Zoi.map() |> Zoi.default(%{}),
              initialized: Zoi.boolean() |> Zoi.default(false)
            },
            coerce: true
          )

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Chat."
  def schema, do: @schema

  @doc """
  Creates a new chat state struct.

  Supported options:
    * `:id`
    * `:user_name`
    * `:adapters` - map `%{telegram: Jido.Chat.Telegram.Adapter, ...}`
    * `:metadata`
  """
  @spec new(keyword() | map()) :: t()
  def new(opts \\ [])

  def new(opts) when is_list(opts), do: opts |> Map.new() |> new()

  def new(opts) when is_map(opts) do
    attrs = %{
      id: opts[:id] || opts["id"] || Jido.Chat.ID.generate!(),
      user_name: opts[:user_name] || opts["user_name"] || "bot",
      adapters: AdapterRegistry.normalize_adapters(opts[:adapters] || opts["adapters"] || %{}),
      metadata: opts[:metadata] || opts["metadata"] || %{},
      thread_state: opts[:thread_state] || opts["thread_state"] || %{},
      channel_state: opts[:channel_state] || opts["channel_state"] || %{}
    }

    Jido.Chat.Schema.parse!(__MODULE__, @schema, attrs)
  end

  @doc "Marks chat instance as initialized and initializes adapters when available."
  @spec initialize(t()) :: t()
  def initialize(%__MODULE__{} = chat) do
    Enum.each(chat.adapters, fn {_name, adapter} ->
      _ = Adapter.initialize(adapter, chat.metadata[:adapter_opts] || [])
    end)

    %{chat | initialized: true}
  end

  @doc "Marks chat instance as shut down and shuts down adapters when available."
  @spec shutdown(t()) :: t()
  def shutdown(%__MODULE__{} = chat) do
    Enum.each(chat.adapters, fn {_name, adapter} ->
      _ = Adapter.shutdown(adapter, chat.metadata[:adapter_opts] || [])
    end)

    %{chat | initialized: false}
  end

  @doc "Registers a new-mention handler."
  @spec on_new_mention(t(), mention_handler()) :: t()
  def on_new_mention(%__MODULE__{} = chat, handler) when is_function(handler) do
    update_in(chat.handlers.mention, &(&1 ++ [handler]))
  end

  @doc "Registers a new-message regex handler."
  @spec on_new_message(t(), Regex.t() | String.t(), message_handler()) :: t()
  def on_new_message(%__MODULE__{} = chat, %Regex{} = pattern, handler)
      when is_function(handler) do
    update_in(chat.handlers.message, &(&1 ++ [{pattern, handler}]))
  end

  def on_new_message(%__MODULE__{} = chat, pattern, handler)
      when is_binary(pattern) and is_function(handler) do
    on_new_message(chat, Regex.compile!(pattern), handler)
  end

  @doc "Registers a subscribed-thread handler."
  @spec on_subscribed_message(t(), subscribed_handler()) :: t()
  def on_subscribed_message(%__MODULE__{} = chat, handler) when is_function(handler) do
    update_in(chat.handlers.subscribed, &(&1 ++ [handler]))
  end

  @doc "Registers a reaction-event handler."
  @spec on_reaction(t(), reaction_handler()) :: t()
  def on_reaction(%__MODULE__{} = chat, handler) when is_function(handler) do
    update_in(chat.handlers.reaction, &(&1 ++ [handler]))
  end

  @doc "Registers an action-event handler."
  @spec on_action(t(), action_handler()) :: t()
  def on_action(%__MODULE__{} = chat, handler) when is_function(handler) do
    update_in(chat.handlers.action, &(&1 ++ [handler]))
  end

  @doc "Registers a modal-submit handler."
  @spec on_modal_submit(t(), modal_submit_handler()) :: t()
  def on_modal_submit(%__MODULE__{} = chat, handler) when is_function(handler) do
    update_in(chat.handlers.modal_submit, &(&1 ++ [handler]))
  end

  @doc "Registers a modal-close handler."
  @spec on_modal_close(t(), modal_close_handler()) :: t()
  def on_modal_close(%__MODULE__{} = chat, handler) when is_function(handler) do
    update_in(chat.handlers.modal_close, &(&1 ++ [handler]))
  end

  @doc "Registers a slash-command handler."
  @spec on_slash_command(t(), slash_command_handler()) :: t()
  def on_slash_command(%__MODULE__{} = chat, handler) when is_function(handler) do
    update_in(chat.handlers.slash_command, &(&1 ++ [handler]))
  end

  @doc "Registers assistant thread started handlers."
  @spec on_assistant_thread_started(t(), assistant_thread_started_handler()) :: t()
  def on_assistant_thread_started(%__MODULE__{} = chat, handler) when is_function(handler) do
    update_in(chat.handlers.assistant_thread_started, &(&1 ++ [handler]))
  end

  @doc "Registers assistant context changed handlers."
  @spec on_assistant_context_changed(t(), assistant_context_changed_handler()) :: t()
  def on_assistant_context_changed(%__MODULE__{} = chat, handler) when is_function(handler) do
    update_in(chat.handlers.assistant_context_changed, &(&1 ++ [handler]))
  end

  @doc "Returns adapter module by name."
  @spec get_adapter(t(), atom()) :: {:ok, module()} | {:error, term()}
  def get_adapter(%__MODULE__{} = chat, adapter_name) when is_atom(adapter_name) do
    AdapterRegistry.resolve(chat, adapter_name)
  end

  @doc "Returns adapter-keyed request-first webhook handlers."
  @spec webhooks(t()) :: %{optional(atom()) => webhook_request_handler()}
  def webhooks(%__MODULE__{} = chat) do
    Enum.reduce(Map.keys(chat.adapters), %{}, fn adapter_name, acc ->
      Map.put(acc, adapter_name, fn request_or_payload, opts ->
        handle_webhook_request(chat, adapter_name, request_or_payload, opts)
      end)
    end)
  end

  @doc "Compatibility helper returning adapter-keyed webhook handlers with explicit chat argument."
  @spec webhooks_with_chat(t()) :: %{optional(atom()) => webhook_request_handler_with_chat()}
  def webhooks_with_chat(%__MODULE__{} = chat) do
    Enum.reduce(Map.keys(chat.adapters), %{}, fn adapter_name, acc ->
      Map.put(acc, adapter_name, fn current_chat, request_or_payload, opts ->
        base_chat = if match?(%__MODULE__{}, current_chat), do: current_chat, else: chat
        handle_webhook_request(base_chat, adapter_name, request_or_payload, opts)
      end)
    end)
  end

  @doc """
  Handles a webhook payload for the given adapter.
  """
  @spec handle_webhook(t(), atom(), map(), keyword()) ::
          {:ok, t(), Incoming.t()} | {:error, term()}
  def handle_webhook(%__MODULE__{} = chat, adapter_name, payload, opts \\ [])
      when is_atom(adapter_name) and is_map(payload) do
    with {:ok, adapter_module} <- AdapterRegistry.resolve(chat, adapter_name) do
      if function_exported?(adapter_module, :handle_webhook, 3) do
        adapter_module.handle_webhook(chat, payload, opts)
      else
        Adapter.handle_webhook(adapter_module, chat, payload, opts)
      end
    end
  end

  @doc """
  Handles a typed webhook request for the given adapter.

  Returns the updated chat state, normalized event envelope, and typed webhook response.
  """
  @spec handle_webhook_request(
          t(),
          atom(),
          WebhookRequest.t() | map(),
          keyword()
        ) ::
          {:ok, t(), EventEnvelope.t() | nil, WebhookResponse.t()}
  def handle_webhook_request(%__MODULE__{} = chat, adapter_name, request_or_payload, opts \\ [])
      when is_atom(adapter_name) and is_list(opts) do
    WebhookPipeline.handle_request(
      chat,
      adapter_name,
      request_or_payload,
      opts,
      &AdapterRegistry.resolve/2,
      &process_event/4
    )
  end

  @doc """
  Opens a DM thread with an adapter when supported.
  """
  @spec open_dm(t(), atom(), String.t() | integer()) :: {:ok, Thread.t()} | {:error, term()}
  def open_dm(%__MODULE__{} = chat, adapter_name, external_user_id) when is_atom(adapter_name) do
    with {:ok, adapter_module} <- AdapterRegistry.resolve(chat, adapter_name) do
      if function_exported?(adapter_module, :open_dm, 2) do
        case adapter_module.open_dm(external_user_id, []) do
          {:ok, external_room_id} ->
            {:ok, thread(chat, adapter_name, external_room_id, is_dm: true)}

          other ->
            other
        end
      else
        {:error, :unsupported}
      end
    end
  end

  @doc "Builds a channel reference from adapter + external channel id."
  @spec channel(t(), atom(), String.t() | integer()) :: ChannelRef.t()
  def channel(%__MODULE__{} = chat, adapter_name, external_id) when is_atom(adapter_name) do
    adapter_module = AdapterRegistry.resolve!(chat, adapter_name)

    ChannelRef.new(%{
      id: "#{adapter_name}:#{external_id}",
      adapter_name: adapter_name,
      adapter: adapter_module,
      external_id: external_id
    })
  end

  @doc "Builds a thread reference from adapter + external room id."
  @spec thread(t(), atom(), String.t() | integer(), keyword()) :: Thread.t()
  def thread(%__MODULE__{} = chat, adapter_name, external_room_id, opts \\ [])
      when is_atom(adapter_name) and is_list(opts) do
    adapter_module = AdapterRegistry.resolve!(chat, adapter_name)
    external_thread_id = opts[:external_thread_id] || opts[:thread_id]

    Thread.new(%{
      id: opts[:id] || thread_id(adapter_name, external_room_id, external_thread_id),
      adapter_name: adapter_name,
      adapter: adapter_module,
      external_room_id: external_room_id,
      external_thread_id: external_thread_id,
      channel_id: "#{adapter_name}:#{external_room_id}",
      is_dm: opts[:is_dm] || false,
      metadata: opts[:metadata] || %{}
    })
  end

  @doc """
  Adapter-internal entrypoint for processing normalized incoming message events.
  """
  @spec process_message(t(), atom(), String.t(), Incoming.t() | map(), keyword()) ::
          {:ok, t(), Incoming.t()} | {:error, term()}
  def process_message(%__MODULE__{} = chat, adapter_name, thread_id, incoming, opts \\ [])
      when is_atom(adapter_name) and is_binary(thread_id) and is_list(opts) do
    EventRouter.process_message(
      chat,
      adapter_name,
      thread_id,
      incoming,
      fn current_chat, normalized_incoming, resolved_thread_id ->
        thread(
          current_chat,
          adapter_name,
          normalized_incoming.external_room_id,
          thread_id: normalized_incoming.external_thread_id,
          id: resolved_thread_id
        )
      end
    )
  end

  @doc "Processes normalized reaction events and dispatches handlers."
  @spec process_reaction(t(), atom(), ReactionEvent.t() | map(), keyword()) ::
          {:ok, t(), ReactionEvent.t()} | {:error, term()}
  def process_reaction(%__MODULE__{} = chat, adapter_name, event, opts \\ [])
      when is_atom(adapter_name) and is_list(opts) do
    with {:ok, reaction} <- EventRouter.ensure_reaction_event(event, adapter_name) do
      {:ok, EventRouter.run_event_handlers(chat, chat.handlers.reaction, reaction), reaction}
    end
  end

  @doc "Processes normalized action events and dispatches handlers."
  @spec process_action(t(), atom(), ActionEvent.t() | map(), keyword()) ::
          {:ok, t(), ActionEvent.t()} | {:error, term()}
  def process_action(%__MODULE__{} = chat, adapter_name, event, opts \\ [])
      when is_atom(adapter_name) and is_list(opts) do
    with {:ok, action} <- EventRouter.ensure_action_event(event, adapter_name) do
      {:ok, EventRouter.run_event_handlers(chat, chat.handlers.action, action), action}
    end
  end

  @doc "Processes normalized modal submit events and dispatches handlers."
  @spec process_modal_submit(t(), atom(), ModalSubmitEvent.t() | map(), keyword()) ::
          {:ok, t(), ModalSubmitEvent.t()} | {:error, term()}
  def process_modal_submit(%__MODULE__{} = chat, adapter_name, event, opts \\ [])
      when is_atom(adapter_name) and is_list(opts) do
    with {:ok, modal_submit} <- EventRouter.ensure_modal_submit_event(event, adapter_name) do
      {:ok, EventRouter.run_event_handlers(chat, chat.handlers.modal_submit, modal_submit),
       modal_submit}
    end
  end

  @doc "Processes normalized modal close events and dispatches handlers."
  @spec process_modal_close(t(), atom(), ModalCloseEvent.t() | map(), keyword()) ::
          {:ok, t(), ModalCloseEvent.t()} | {:error, term()}
  def process_modal_close(%__MODULE__{} = chat, adapter_name, event, opts \\ [])
      when is_atom(adapter_name) and is_list(opts) do
    with {:ok, modal_close} <- EventRouter.ensure_modal_close_event(event, adapter_name) do
      {:ok, EventRouter.run_event_handlers(chat, chat.handlers.modal_close, modal_close),
       modal_close}
    end
  end

  @doc "Processes normalized slash command events and dispatches handlers."
  @spec process_slash_command(t(), atom(), SlashCommandEvent.t() | map(), keyword()) ::
          {:ok, t(), SlashCommandEvent.t()} | {:error, term()}
  def process_slash_command(%__MODULE__{} = chat, adapter_name, event, opts \\ [])
      when is_atom(adapter_name) and is_list(opts) do
    with {:ok, slash_command} <- EventRouter.ensure_slash_command_event(event, adapter_name) do
      {:ok, EventRouter.run_event_handlers(chat, chat.handlers.slash_command, slash_command),
       slash_command}
    end
  end

  @doc """
  Canonical typed event router used by webhook and gateway ingestion.
  """
  @spec process_event(t(), atom(), EventEnvelope.t() | map(), keyword()) ::
          {:ok, t(), EventEnvelope.t()} | {:error, term()}
  def process_event(%__MODULE__{} = chat, adapter_name, event, opts \\ [])
      when is_atom(adapter_name) and is_list(opts) do
    dispatchers = %{
      process_message: &process_message/5,
      process_reaction: &process_reaction/4,
      process_action: &process_action/4,
      process_modal_submit: &process_modal_submit/4,
      process_modal_close: &process_modal_close/4,
      process_slash_command: &process_slash_command/4,
      process_assistant_thread_started: &process_assistant_thread_started/3,
      process_assistant_context_changed: &process_assistant_context_changed/3
    }

    with {:ok, envelope} <- EventRouter.ensure_event_envelope(event, adapter_name),
         {:ok, routed_chat, routed_payload} <-
           EventRouter.route_event(chat, adapter_name, envelope, opts, dispatchers) do
      {:ok, routed_chat, EventRouter.with_envelope_payload(envelope, routed_payload)}
    end
  end

  @doc "Processes assistant thread started events and dispatches handlers."
  @spec process_assistant_thread_started(
          t(),
          atom(),
          AssistantThreadStartedEvent.t() | map()
        ) ::
          {:ok, t(), AssistantThreadStartedEvent.t()} | {:error, term()}
  def process_assistant_thread_started(%__MODULE__{} = chat, adapter_name, event)
      when is_atom(adapter_name) do
    with {:ok, assistant_event} <-
           EventRouter.ensure_assistant_thread_started_event(event, adapter_name) do
      {:ok,
       EventRouter.run_event_handlers(
         chat,
         chat.handlers.assistant_thread_started,
         assistant_event
       ), assistant_event}
    end
  end

  @doc "Processes assistant context changed events and dispatches handlers."
  @spec process_assistant_context_changed(
          t(),
          atom(),
          AssistantContextChangedEvent.t() | map()
        ) ::
          {:ok, t(), AssistantContextChangedEvent.t()} | {:error, term()}
  def process_assistant_context_changed(%__MODULE__{} = chat, adapter_name, event)
      when is_atom(adapter_name) do
    with {:ok, assistant_event} <-
           EventRouter.ensure_assistant_context_changed_event(event, adapter_name) do
      {:ok,
       EventRouter.run_event_handlers(
         chat,
         chat.handlers.assistant_context_changed,
         assistant_event
       ), assistant_event}
    end
  end

  @doc "Returns adapter capability matrix wrapped in typed struct."
  @spec adapter_capabilities(t(), atom()) :: {:ok, CapabilityMatrix.t()} | {:error, term()}
  def adapter_capabilities(%__MODULE__{} = chat, adapter_name) when is_atom(adapter_name) do
    with {:ok, adapter_module} <- AdapterRegistry.resolve(chat, adapter_name) do
      {:ok,
       CapabilityMatrix.new(%{
         adapter_name: adapter_name,
         capabilities: Adapter.capabilities(adapter_module)
       })}
    end
  end

  @doc "Returns true when a thread id is currently subscribed."
  @spec subscribed?(t(), String.t()) :: boolean()
  def subscribed?(%__MODULE__{} = chat, thread_id),
    do: MapSet.member?(chat.subscriptions, thread_id)

  @doc "Subscribes a thread id."
  @spec subscribe(t(), String.t()) :: t()
  def subscribe(%__MODULE__{} = chat, thread_id),
    do: %{chat | subscriptions: MapSet.put(chat.subscriptions, thread_id)}

  @doc "Unsubscribes a thread id."
  @spec unsubscribe(t(), String.t()) :: t()
  def unsubscribe(%__MODULE__{} = chat, thread_id),
    do: %{chat | subscriptions: MapSet.delete(chat.subscriptions, thread_id)}

  @doc "Gets thread state map by id."
  @spec thread_state(t(), String.t()) :: map()
  def thread_state(%__MODULE__{} = chat, thread_id),
    do: Map.get(chat.thread_state, thread_id, %{})

  @doc "Sets thread state map by id."
  @spec put_thread_state(t(), String.t(), map()) :: t()
  def put_thread_state(%__MODULE__{} = chat, thread_id, state) when is_map(state) do
    %{chat | thread_state: Map.put(chat.thread_state, thread_id, state)}
  end

  @doc "Gets channel state map by id."
  @spec channel_state(t(), String.t()) :: map()
  def channel_state(%__MODULE__{} = chat, channel_id),
    do: Map.get(chat.channel_state, channel_id, %{})

  @doc "Sets channel state map by id."
  @spec put_channel_state(t(), String.t(), map()) :: t()
  def put_channel_state(%__MODULE__{} = chat, channel_id, state) when is_map(state) do
    %{chat | channel_state: Map.put(chat.channel_state, channel_id, state)}
  end

  @doc "Compatibility constructor for legacy message shape."
  @spec new_message(map()) :: LegacyMessage.t()
  def new_message(attrs), do: LegacyMessage.new(attrs)

  @doc "Creates a normalized Chat SDK-style message."
  @spec message(map()) :: Message.t()
  def message(attrs), do: Message.new(attrs)

  @spec new_room(map()) :: Room.t()
  def new_room(attrs), do: Room.new(attrs)

  @spec new_participant(map()) :: Participant.t()
  def new_participant(attrs), do: Participant.new(attrs)

  @spec text(String.t()) :: Text.t()
  def text(value), do: Text.new(value)

  @doc "Serializes chat state to a revivable map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = chat), do: Serialization.to_map(chat)

  @doc "Builds chat state from serialized map."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: Serialization.from_map(map)

  @doc "Returns a reviver function for serialized core structs."
  @spec reviver() :: (map() -> term())
  def reviver, do: Serialization.reviver()

  @doc false
  @spec revive(map()) :: term()
  def revive(map), do: Serialization.revive(map)

  defp thread_id(adapter_name, external_room_id, nil), do: "#{adapter_name}:#{external_room_id}"

  defp thread_id(adapter_name, external_room_id, external_thread_id),
    do: "#{adapter_name}:#{external_room_id}:#{external_thread_id}"
end
