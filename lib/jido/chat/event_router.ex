defmodule Jido.Chat.EventRouter do
  @moduledoc false

  alias Jido.Chat.{EventEnvelope, EventNormalizer, HandlerDispatch, Incoming, Thread}

  @spec process_message(
          map(),
          atom(),
          String.t(),
          Incoming.t() | map(),
          (map(), Incoming.t(), String.t() -> Thread.t()),
          Jido.Chat.MessageContext.t() | nil
        ) ::
          {:ok, map(), Incoming.t()} | {:error, term()}
  def process_message(chat, adapter_name, thread_id, incoming, build_thread, context \\ nil) do
    HandlerDispatch.process_message(chat, adapter_name, thread_id, incoming, build_thread, context)
  end

  @spec run_event_handlers(map(), list(), term()) :: map()
  def run_event_handlers(chat, handlers, event),
    do: HandlerDispatch.run_event_handlers(chat, handlers, event)

  @spec ensure_incoming(Incoming.t() | map() | term()) :: {:ok, Incoming.t()} | {:error, term()}
  def ensure_incoming(input), do: EventNormalizer.ensure_incoming(input)

  @spec ensure_message_updated_event(term(), atom()) :: {:ok, term()} | {:error, term()}
  def ensure_message_updated_event(event, adapter_name),
    do: EventNormalizer.ensure_message_updated_event(event, adapter_name)

  @spec ensure_message_deleted_event(term(), atom()) :: {:ok, term()} | {:error, term()}
  def ensure_message_deleted_event(event, adapter_name),
    do: EventNormalizer.ensure_message_deleted_event(event, adapter_name)

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
        %EventEnvelope{event_type: :message_updated} = envelope,
        opts,
        dispatchers
      ) do
    dispatchers.process_message_updated.(
      chat,
      adapter_name,
      lifecycle_payload(envelope),
      opts
    )
  end

  def route_event(
        chat,
        adapter_name,
        %EventEnvelope{event_type: :message_deleted} = envelope,
        opts,
        dispatchers
      ) do
    dispatchers.process_message_deleted.(
      chat,
      adapter_name,
      lifecycle_payload(envelope),
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

  defp lifecycle_payload(%EventEnvelope{} = envelope) do
    case envelope.payload || %{} do
      payload when is_map(payload) ->
        payload
        |> put_context_if_missing(:thread_id, envelope.thread_id)
        |> put_context_if_missing(:channel_id, envelope.channel_id)
        |> put_context_if_missing(:message_id, envelope.message_id)
        |> merge_context(:metadata, envelope.metadata)
        |> merge_context(:raw, envelope.raw)

      payload ->
        payload
    end
  end

  defp put_context_if_missing(payload, _key, nil), do: payload

  defp put_context_if_missing(payload, key, value) do
    if Map.get(payload, key) || Map.get(payload, Atom.to_string(key)) do
      payload
    else
      payload |> Map.delete(Atom.to_string(key)) |> Map.put(key, value)
    end
  end

  defp merge_context(payload, key, envelope_context) do
    string_key = Atom.to_string(key)

    if envelope_context in [nil, %{}] and is_map(Map.get(payload, key)) and
         not Map.has_key?(payload, string_key) do
      payload
    else
      merge_context_maps(payload, key, string_key, envelope_context)
    end
  end

  defp merge_context_maps(payload, key, string_key, envelope_context) do
    payload_context = Map.get(payload, key) || Map.get(payload, string_key)

    merged_context =
      if is_map(payload_context) do
        Map.merge(envelope_context || %{}, payload_context)
      else
        payload_context || envelope_context || %{}
      end

    payload
    |> Map.delete(string_key)
    |> Map.put(key, merged_context)
  end

  @spec with_envelope_payload(EventEnvelope.t(), term()) :: EventEnvelope.t()
  def with_envelope_payload(%EventEnvelope{} = envelope, payload),
    do: EventNormalizer.with_envelope_payload(envelope, payload)
end
