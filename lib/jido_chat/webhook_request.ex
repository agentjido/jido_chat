defmodule Jido.Chat.WebhookRequest do
  @moduledoc """
  Typed webhook request envelope used for adapter verification and parsing.
  """

  alias Jido.Chat.Wire

  @schema Zoi.struct(
            __MODULE__,
            %{
              adapter_name: Zoi.atom() |> Zoi.nullish(),
              method: Zoi.string() |> Zoi.default("POST"),
              path: Zoi.string() |> Zoi.nullish(),
              headers: Zoi.map() |> Zoi.default(%{}),
              payload: Zoi.map() |> Zoi.default(%{}),
              query: Zoi.map() |> Zoi.default(%{}),
              raw: Zoi.any() |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for WebhookRequest."
  def schema, do: @schema

  @doc "Creates a typed webhook request from raw map or HTTP-style request fields."
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    attrs
    |> normalize_shape()
    |> normalize_headers()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Gets a normalized request header value."
  @spec header(t(), String.t()) :: String.t() | nil
  def header(%__MODULE__{} = request, key) when is_binary(key) do
    request.headers[String.downcase(key)]
  end

  @doc "Serializes webhook request into plain map with type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = request) do
    request
    |> Map.from_struct()
    |> Wire.to_plain()
    |> Map.put("__type__", "webhook_request")
  end

  @doc "Builds webhook request from serialized data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: new(map)

  defp normalize_shape(attrs) do
    payload = attrs[:payload] || attrs["payload"]

    if is_map(payload) do
      attrs
    else
      %{
        adapter_name: attrs[:adapter_name] || attrs["adapter_name"],
        method: attrs[:method] || attrs["method"] || "POST",
        path: attrs[:path] || attrs["path"],
        headers: attrs[:headers] || attrs["headers"] || %{},
        payload: attrs,
        query: attrs[:query] || attrs["query"] || %{},
        raw: attrs,
        metadata: attrs[:metadata] || attrs["metadata"] || %{}
      }
    end
  end

  defp normalize_headers(attrs) do
    headers = attrs[:headers] || attrs["headers"] || %{}

    normalized =
      headers
      |> Enum.map(fn {key, value} -> {key |> to_string() |> String.downcase(), value} end)
      |> Map.new()

    Map.put(attrs, :headers, normalized)
  end
end
