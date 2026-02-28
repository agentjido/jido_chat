defmodule Jido.Chat.IngressResult do
  @moduledoc """
  Transport-agnostic typed inbound routing result.

  Supports both request-based inputs (for example webhook HTTP requests)
  and event-based inputs (for example polling or gateway listeners).
  """

  alias Jido.Chat.{EventEnvelope, WebhookRequest, WebhookResponse, Wire}

  @schema Zoi.struct(
            __MODULE__,
            %{
              chat: Zoi.any(),
              adapter_name: Zoi.atom() |> Zoi.nullish(),
              event: Zoi.any() |> Zoi.nullish(),
              response: Zoi.any() |> Zoi.nullish(),
              request: Zoi.any() |> Zoi.nullish(),
              mode: Zoi.enum([:request, :event]) |> Zoi.default(:event),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type mode :: :request | :event
  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for IngressResult."
  def schema, do: @schema

  @doc "Creates a typed ingress result."
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs), do: Jido.Chat.Schema.parse!(__MODULE__, @schema, attrs)

  @doc "Serializes ingress result into a plain map with type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = result) do
    %{
      chat: serialize_chat(result.chat),
      adapter_name: result.adapter_name,
      event: serialize_event(result.event),
      response: serialize_response(result.response),
      request: serialize_request(result.request),
      mode: result.mode,
      metadata: Wire.to_plain(result.metadata)
    }
    |> Wire.to_plain()
    |> Map.put("__type__", "ingress_result")
  end

  @doc "Builds ingress result from serialized data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    new(%{
      chat: deserialize_chat(map[:chat] || map["chat"]),
      adapter_name: map[:adapter_name] || map["adapter_name"],
      event: deserialize_event(map[:event] || map["event"]),
      response: deserialize_response(map[:response] || map["response"]),
      request: deserialize_request(map[:request] || map["request"]),
      mode: map[:mode] || map["mode"] || :event,
      metadata: map[:metadata] || map["metadata"] || %{}
    })
  end

  defp serialize_chat(%Jido.Chat{} = chat), do: Jido.Chat.to_map(chat)
  defp serialize_chat(other), do: Wire.to_plain(other)

  defp serialize_event(%EventEnvelope{} = envelope), do: EventEnvelope.to_map(envelope)
  defp serialize_event(other), do: Wire.to_plain(other)

  defp serialize_response(%WebhookResponse{} = response), do: WebhookResponse.to_map(response)
  defp serialize_response(other), do: Wire.to_plain(other)

  defp serialize_request(%WebhookRequest{} = request), do: WebhookRequest.to_map(request)
  defp serialize_request(other), do: Wire.to_plain(other)

  defp deserialize_chat(map) when is_map(map) do
    case map[:__type__] || map["__type__"] do
      "chat" -> Jido.Chat.from_map(map)
      _ -> map
    end
  end

  defp deserialize_chat(other), do: other

  defp deserialize_event(map) when is_map(map) do
    case map[:__type__] || map["__type__"] do
      "event_envelope" -> EventEnvelope.from_map(map)
      _ -> map
    end
  end

  defp deserialize_event(other), do: other

  defp deserialize_response(map) when is_map(map) do
    case map[:__type__] || map["__type__"] do
      "webhook_response" -> WebhookResponse.from_map(map)
      _ -> map
    end
  end

  defp deserialize_response(other), do: other

  defp deserialize_request(map) when is_map(map) do
    case map[:__type__] || map["__type__"] do
      "webhook_request" -> WebhookRequest.from_map(map)
      _ -> map
    end
  end

  defp deserialize_request(other), do: other
end
