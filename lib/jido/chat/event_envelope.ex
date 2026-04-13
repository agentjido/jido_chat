defmodule Jido.Chat.EventEnvelope do
  @moduledoc """
  Canonical normalized event envelope used by webhook and gateway ingestion.
  """

  alias Jido.Chat.{
    ActionEvent,
    AssistantContextChangedEvent,
    AssistantThreadStartedEvent,
    Incoming,
    ModalCloseEvent,
    ModalSubmitEvent,
    ReactionEvent,
    SlashCommandEvent,
    Wire
  }

  @event_types [
    :message,
    :reaction,
    :action,
    :modal_submit,
    :modal_close,
    :slash_command,
    :assistant_thread_started,
    :assistant_context_changed
  ]

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              adapter_name: Zoi.atom() |> Zoi.nullish(),
              event_type: Zoi.enum(@event_types),
              thread_id: Zoi.string() |> Zoi.nullish(),
              channel_id: Zoi.string() |> Zoi.nullish(),
              message_id: Zoi.string() |> Zoi.nullish(),
              payload: Zoi.any() |> Zoi.nullish(),
              raw: Zoi.map() |> Zoi.default(%{}),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type event_type ::
          :message
          | :reaction
          | :action
          | :modal_submit
          | :modal_close
          | :slash_command
          | :assistant_thread_started
          | :assistant_context_changed

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for EventEnvelope."
  def schema, do: @schema

  @doc "Creates a canonical event envelope."
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    attrs
    |> Map.put_new(:id, Jido.Chat.ID.generate!())
    |> maybe_normalize_event_type()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Serializes event envelope into a plain map with type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = envelope) do
    envelope
    |> Map.from_struct()
    |> Map.update!(:payload, &serialize_payload/1)
    |> Wire.to_plain()
    |> Map.put("__type__", "event_envelope")
  end

  @doc "Builds event envelope from serialized data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    payload = map[:payload] || map["payload"]

    map
    |> Map.drop(["__type__", :__type__])
    |> Map.delete("payload")
    |> Map.put(:payload, deserialize_payload(payload))
    |> new()
  end

  defp maybe_normalize_event_type(attrs) do
    case attrs[:event_type] || attrs["event_type"] do
      event_type when is_atom(event_type) ->
        attrs

      event_type when is_binary(event_type) ->
        Map.put(attrs, :event_type, event_type |> String.trim() |> String.to_existing_atom())

      _ ->
        attrs
    end
  rescue
    ArgumentError -> attrs
  end

  defp serialize_payload(%Incoming{} = payload), do: Incoming.to_map(payload)
  defp serialize_payload(%ReactionEvent{} = payload), do: ReactionEvent.to_map(payload)
  defp serialize_payload(%ActionEvent{} = payload), do: ActionEvent.to_map(payload)
  defp serialize_payload(%ModalSubmitEvent{} = payload), do: ModalSubmitEvent.to_map(payload)
  defp serialize_payload(%ModalCloseEvent{} = payload), do: ModalCloseEvent.to_map(payload)
  defp serialize_payload(%SlashCommandEvent{} = payload), do: SlashCommandEvent.to_map(payload)

  defp serialize_payload(%AssistantThreadStartedEvent{} = payload),
    do: AssistantThreadStartedEvent.to_map(payload)

  defp serialize_payload(%AssistantContextChangedEvent{} = payload),
    do: AssistantContextChangedEvent.to_map(payload)

  defp serialize_payload(payload), do: Wire.to_plain(payload)

  defp deserialize_payload(%{"__type__" => "incoming"} = payload), do: Incoming.from_map(payload)

  defp deserialize_payload(%{"__type__" => "reaction_event"} = payload),
    do: ReactionEvent.from_map(payload)

  defp deserialize_payload(%{"__type__" => "action_event"} = payload),
    do: ActionEvent.from_map(payload)

  defp deserialize_payload(%{"__type__" => "modal_submit_event"} = payload),
    do: ModalSubmitEvent.from_map(payload)

  defp deserialize_payload(%{"__type__" => "modal_close_event"} = payload),
    do: ModalCloseEvent.from_map(payload)

  defp deserialize_payload(%{"__type__" => "slash_command_event"} = payload),
    do: SlashCommandEvent.from_map(payload)

  defp deserialize_payload(%{"__type__" => "assistant_thread_started_event"} = payload),
    do: AssistantThreadStartedEvent.from_map(payload)

  defp deserialize_payload(%{"__type__" => "assistant_context_changed_event"} = payload),
    do: AssistantContextChangedEvent.from_map(payload)

  defp deserialize_payload(payload), do: payload
end
