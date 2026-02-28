defmodule Jido.Chat.EventRouter do
  @moduledoc false

  alias Jido.Chat.{EventEnvelope, EventNormalizer, HandlerDispatch, Incoming, Thread}

  @spec process_message(map(), atom(), String.t(), Incoming.t() | map(), (map(),
                                                                          Incoming.t(),
                                                                          String.t() ->
                                                                            Thread.t())) ::
          {:ok, map(), Incoming.t()} | {:error, term()}
  def process_message(chat, adapter_name, thread_id, incoming, build_thread) do
    HandlerDispatch.process_message(chat, adapter_name, thread_id, incoming, build_thread)
  end

  @spec run_event_handlers(map(), list(), term()) :: map()
  def run_event_handlers(chat, handlers, event),
    do: HandlerDispatch.run_event_handlers(chat, handlers, event)

  @spec ensure_incoming(Incoming.t() | map() | term()) :: {:ok, Incoming.t()} | {:error, term()}
  def ensure_incoming(input), do: EventNormalizer.ensure_incoming(input)

  @spec ensure_reaction_event(term(), atom()) :: {:ok, term()} | {:error, term()}
  def ensure_reaction_event(event, adapter_name),
    do: EventNormalizer.ensure_reaction_event(event, adapter_name)

  @spec ensure_action_event(term(), atom()) :: {:ok, term()} | {:error, term()}
  def ensure_action_event(event, adapter_name),
    do: EventNormalizer.ensure_action_event(event, adapter_name)

  @spec ensure_modal_submit_event(term(), atom()) :: {:ok, term()} | {:error, term()}
  def ensure_modal_submit_event(event, adapter_name),
    do: EventNormalizer.ensure_modal_submit_event(event, adapter_name)

  @spec ensure_modal_close_event(term(), atom()) :: {:ok, term()} | {:error, term()}
  def ensure_modal_close_event(event, adapter_name),
    do: EventNormalizer.ensure_modal_close_event(event, adapter_name)

  @spec ensure_slash_command_event(term(), atom()) :: {:ok, term()} | {:error, term()}
  def ensure_slash_command_event(event, adapter_name),
    do: EventNormalizer.ensure_slash_command_event(event, adapter_name)

  @spec ensure_assistant_thread_started_event(term(), atom()) :: {:ok, term()} | {:error, term()}
  def ensure_assistant_thread_started_event(event, adapter_name),
    do: EventNormalizer.ensure_assistant_thread_started_event(event, adapter_name)

  @spec ensure_assistant_context_changed_event(term(), atom()) ::
          {:ok, term()} | {:error, term()}
  def ensure_assistant_context_changed_event(event, adapter_name),
    do: EventNormalizer.ensure_assistant_context_changed_event(event, adapter_name)

  @spec ensure_event_envelope(EventEnvelope.t() | map() | term(), atom()) ::
          {:ok, EventEnvelope.t()} | {:error, term()}
  def ensure_event_envelope(event, adapter_name),
    do: EventNormalizer.ensure_event_envelope(event, adapter_name)

  @spec route_event(map(), atom(), EventEnvelope.t(), keyword(), map()) ::
          {:ok, map(), term()} | {:error, term()}
  def route_event(
        chat,
        adapter_name,
        %EventEnvelope{event_type: :message} = envelope,
        opts,
        dispatchers
      ) do
    payload = envelope.payload || envelope.raw || %{}

    with {:ok, incoming} <- EventNormalizer.ensure_incoming(payload),
         thread_id <- envelope.thread_id || EventNormalizer.thread_id_from(adapter_name, incoming),
         {:ok, routed_chat, routed_incoming} <-
           dispatchers.process_message.(chat, adapter_name, thread_id, incoming, opts) do
      {:ok, routed_chat, routed_incoming}
    end
  end

  def route_event(
        chat,
        adapter_name,
        %EventEnvelope{event_type: :reaction} = envelope,
        opts,
        dispatchers
      ) do
    dispatchers.process_reaction.(
      chat,
      adapter_name,
      envelope.payload || envelope.raw || %{},
      opts
    )
  end

  def route_event(
        chat,
        adapter_name,
        %EventEnvelope{event_type: :action} = envelope,
        opts,
        dispatchers
      ) do
    dispatchers.process_action.(chat, adapter_name, envelope.payload || envelope.raw || %{}, opts)
  end

  def route_event(
        chat,
        adapter_name,
        %EventEnvelope{event_type: :modal_submit} = envelope,
        opts,
        dispatchers
      ) do
    dispatchers.process_modal_submit.(
      chat,
      adapter_name,
      envelope.payload || envelope.raw || %{},
      opts
    )
  end

  def route_event(
        chat,
        adapter_name,
        %EventEnvelope{event_type: :modal_close} = envelope,
        opts,
        dispatchers
      ) do
    dispatchers.process_modal_close.(
      chat,
      adapter_name,
      envelope.payload || envelope.raw || %{},
      opts
    )
  end

  def route_event(
        chat,
        adapter_name,
        %EventEnvelope{event_type: :slash_command} = envelope,
        opts,
        dispatchers
      ) do
    dispatchers.process_slash_command.(
      chat,
      adapter_name,
      envelope.payload || envelope.raw || %{},
      opts
    )
  end

  def route_event(
        chat,
        adapter_name,
        %EventEnvelope{event_type: :assistant_thread_started} = envelope,
        _opts,
        dispatchers
      ) do
    dispatchers.process_assistant_thread_started.(
      chat,
      adapter_name,
      envelope.payload || envelope.raw
    )
  end

  def route_event(
        chat,
        adapter_name,
        %EventEnvelope{event_type: :assistant_context_changed} = envelope,
        _opts,
        dispatchers
      ) do
    dispatchers.process_assistant_context_changed.(
      chat,
      adapter_name,
      envelope.payload || envelope.raw
    )
  end

  def route_event(_chat, _adapter_name, %EventEnvelope{} = envelope, _opts, _dispatchers),
    do: {:error, {:unsupported_event_type, envelope.event_type}}

  @spec with_envelope_payload(EventEnvelope.t(), term()) :: EventEnvelope.t()
  def with_envelope_payload(%EventEnvelope{} = envelope, payload),
    do: EventNormalizer.with_envelope_payload(envelope, payload)
end
