defmodule Jido.Chat.EventNormalizer do
  @moduledoc false

  alias Jido.Chat.{
    ActionEvent,
    Author,
    AssistantContextChangedEvent,
    AssistantThreadStartedEvent,
    EventEnvelope,
    Incoming,
    ModalCloseEvent,
    ModalSubmitEvent,
    ReactionEvent,
    SlashCommandEvent
  }

  @spec ensure_incoming(Incoming.t() | map() | term()) :: {:ok, Incoming.t()} | {:error, term()}
  def ensure_incoming(%Incoming{} = incoming), do: {:ok, incoming}
  def ensure_incoming(map) when is_map(map), do: {:ok, Incoming.new(map)}
  def ensure_incoming(other), do: {:error, {:invalid_incoming, other}}

  @spec ensure_reaction_event(ReactionEvent.t() | map() | term(), atom()) ::
          {:ok, ReactionEvent.t()} | {:error, term()}
  def ensure_reaction_event(%ReactionEvent{} = event, _adapter_name), do: {:ok, event}

  def ensure_reaction_event(map, adapter_name) when is_map(map),
    do: ensure_event_struct(map, adapter_name, ReactionEvent, :invalid_reaction_event)

  def ensure_reaction_event(other, _adapter_name), do: {:error, {:invalid_reaction_event, other}}

  @spec ensure_action_event(ActionEvent.t() | map() | term(), atom()) ::
          {:ok, ActionEvent.t()} | {:error, term()}
  def ensure_action_event(%ActionEvent{} = event, _adapter_name), do: {:ok, event}

  def ensure_action_event(map, adapter_name) when is_map(map),
    do: ensure_event_struct(map, adapter_name, ActionEvent, :invalid_action_event)

  def ensure_action_event(other, _adapter_name), do: {:error, {:invalid_action_event, other}}

  @spec ensure_modal_submit_event(ModalSubmitEvent.t() | map() | term(), atom()) ::
          {:ok, ModalSubmitEvent.t()} | {:error, term()}
  def ensure_modal_submit_event(%ModalSubmitEvent{} = event, _adapter_name), do: {:ok, event}

  def ensure_modal_submit_event(map, adapter_name) when is_map(map),
    do: ensure_event_struct(map, adapter_name, ModalSubmitEvent, :invalid_modal_submit_event)

  def ensure_modal_submit_event(other, _adapter_name),
    do: {:error, {:invalid_modal_submit_event, other}}

  @spec ensure_modal_close_event(ModalCloseEvent.t() | map() | term(), atom()) ::
          {:ok, ModalCloseEvent.t()} | {:error, term()}
  def ensure_modal_close_event(%ModalCloseEvent{} = event, _adapter_name), do: {:ok, event}

  def ensure_modal_close_event(map, adapter_name) when is_map(map),
    do: ensure_event_struct(map, adapter_name, ModalCloseEvent, :invalid_modal_close_event)

  def ensure_modal_close_event(other, _adapter_name),
    do: {:error, {:invalid_modal_close_event, other}}

  @spec ensure_slash_command_event(SlashCommandEvent.t() | map() | term(), atom()) ::
          {:ok, SlashCommandEvent.t()} | {:error, term()}
  def ensure_slash_command_event(%SlashCommandEvent{} = event, _adapter_name), do: {:ok, event}

  def ensure_slash_command_event(map, adapter_name) when is_map(map),
    do: ensure_event_struct(map, adapter_name, SlashCommandEvent, :invalid_slash_command_event)

  def ensure_slash_command_event(other, _adapter_name),
    do: {:error, {:invalid_slash_command_event, other}}

  @spec ensure_assistant_thread_started_event(
          AssistantThreadStartedEvent.t() | map() | term(),
          atom()
        ) ::
          {:ok, AssistantThreadStartedEvent.t()} | {:error, term()}
  def ensure_assistant_thread_started_event(
        %AssistantThreadStartedEvent{} = event,
        _adapter_name
      ),
      do: {:ok, event}

  def ensure_assistant_thread_started_event(map, adapter_name) when is_map(map) do
    {:ok,
     AssistantThreadStartedEvent.new(
       map
       |> Map.put_new(:adapter_name, adapter_name)
       |> Map.put_new(:thread_id, "unknown")
     )}
  end

  def ensure_assistant_thread_started_event(other, _adapter_name),
    do: {:error, {:invalid_assistant_thread_started_event, other}}

  @spec ensure_assistant_context_changed_event(
          AssistantContextChangedEvent.t() | map() | term(),
          atom()
        ) ::
          {:ok, AssistantContextChangedEvent.t()} | {:error, term()}
  def ensure_assistant_context_changed_event(
        %AssistantContextChangedEvent{} = event,
        _adapter_name
      ),
      do: {:ok, event}

  def ensure_assistant_context_changed_event(map, adapter_name) when is_map(map) do
    {:ok,
     AssistantContextChangedEvent.new(
       map
       |> Map.put_new(:adapter_name, adapter_name)
       |> Map.put_new(:thread_id, "unknown")
     )}
  end

  def ensure_assistant_context_changed_event(other, _adapter_name),
    do: {:error, {:invalid_assistant_context_changed_event, other}}

  @spec ensure_event_envelope(EventEnvelope.t() | map() | term(), atom()) ::
          {:ok, EventEnvelope.t()} | {:error, term()}
  def ensure_event_envelope(%EventEnvelope{} = envelope, _adapter_name), do: {:ok, envelope}

  def ensure_event_envelope(map, adapter_name) when is_map(map) do
    event_type =
      map[:event_type] || map["event_type"] || infer_event_type(map[:payload] || map["payload"])

    {:ok,
     EventEnvelope.new(
       map
       |> Map.put_new(:adapter_name, adapter_name)
       |> Map.put_new(:event_type, event_type || :message)
       |> Map.put_new(:raw, map[:raw] || map["raw"] || %{})
     )}
  end

  def ensure_event_envelope(other, _adapter_name), do: {:error, {:invalid_event_envelope, other}}

  @spec thread_id_from(atom(), Incoming.t()) :: String.t()
  def thread_id_from(adapter_name, %Incoming{} = incoming) do
    if incoming.external_thread_id do
      "#{adapter_name}:#{incoming.external_room_id}:#{incoming.external_thread_id}"
    else
      "#{adapter_name}:#{incoming.external_room_id}"
    end
  end

  @spec with_envelope_payload(EventEnvelope.t(), term()) :: EventEnvelope.t()
  def with_envelope_payload(%EventEnvelope{} = envelope, payload) do
    %{
      envelope
      | payload: payload,
        thread_id: envelope.thread_id || payload_thread_id(envelope.adapter_name, payload),
        channel_id: envelope.channel_id || payload_channel_id(payload),
        message_id: envelope.message_id || payload_message_id(payload)
    }
  end

  defp ensure_event_struct(map, adapter_name, mod, error_tag) when is_map(map) do
    {:ok,
     map
     |> normalize_event_user()
     |> Map.put_new(:adapter_name, adapter_name)
     |> mod.new()}
  rescue
    _ -> {:error, {error_tag, map}}
  end

  defp normalize_event_user(map) when is_map(map) do
    case map[:user] || map["user"] do
      %Author{} ->
        map

      %{} = user ->
        normalized_user = %{
          user_id:
            to_string(user[:user_id] || user["user_id"] || user[:id] || user["id"] || "unknown"),
          user_name:
            user[:user_name] || user["user_name"] || user[:username] || user["username"] ||
              to_string(user[:id] || user["id"] || "unknown"),
          full_name:
            user[:full_name] || user["full_name"] || user[:name] || user["name"] ||
              user[:global_name] || user["global_name"],
          is_bot: user[:is_bot] || user["is_bot"] || false,
          is_me: user[:is_me] || user["is_me"] || false
        }

        Map.put(map, :user, Author.new(normalized_user))

      _ ->
        map
    end
  end

  defp infer_event_type(nil), do: nil

  defp infer_event_type(payload) when is_map(payload) do
    cond do
      Map.has_key?(payload, :emoji) or Map.has_key?(payload, "emoji") -> :reaction
      Map.has_key?(payload, :action_id) or Map.has_key?(payload, "action_id") -> :action
      Map.has_key?(payload, :callback_id) or Map.has_key?(payload, "callback_id") -> :modal_submit
      Map.has_key?(payload, :command) or Map.has_key?(payload, "command") -> :slash_command
      true -> :message
    end
  end

  defp infer_event_type(_), do: :message

  defp payload_thread_id(adapter_name, %Incoming{} = incoming) do
    if incoming.external_thread_id do
      "#{adapter_name}:#{incoming.external_room_id}:#{incoming.external_thread_id}"
    else
      "#{adapter_name}:#{incoming.external_room_id}"
    end
  end

  defp payload_thread_id(_adapter_name, %ReactionEvent{} = payload), do: payload.thread_id
  defp payload_thread_id(_adapter_name, %ActionEvent{} = payload), do: payload.thread_id
  defp payload_thread_id(_adapter_name, %ModalSubmitEvent{}), do: nil
  defp payload_thread_id(_adapter_name, %ModalCloseEvent{}), do: nil
  defp payload_thread_id(_adapter_name, %SlashCommandEvent{}), do: nil

  defp payload_thread_id(_adapter_name, %AssistantThreadStartedEvent{} = payload),
    do: payload.thread_id

  defp payload_thread_id(_adapter_name, %AssistantContextChangedEvent{} = payload),
    do: payload.thread_id

  defp payload_thread_id(_adapter_name, _), do: nil

  defp payload_channel_id(%Incoming{} = incoming), do: stringify(incoming.external_room_id)
  defp payload_channel_id(%SlashCommandEvent{} = payload), do: payload.channel_id
  defp payload_channel_id(_), do: nil

  defp payload_message_id(%Incoming{} = incoming), do: stringify(incoming.external_message_id)
  defp payload_message_id(%ReactionEvent{} = payload), do: payload.message_id
  defp payload_message_id(%ActionEvent{} = payload), do: payload.message_id
  defp payload_message_id(_), do: nil

  defp stringify(nil), do: nil
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: to_string(value)
end
