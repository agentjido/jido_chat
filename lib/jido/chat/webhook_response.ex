defmodule Jido.Chat.WebhookResponse do
  @moduledoc """
  Typed webhook response envelope.
  """

  alias Jido.Chat.Wire

  @schema Zoi.struct(
            __MODULE__,
            %{
              status: Zoi.integer() |> Zoi.default(200),
              headers: Zoi.map() |> Zoi.default(%{}),
              body: Zoi.any() |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for WebhookResponse."
  def schema, do: @schema

  @doc "Creates a typed webhook response envelope."
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs), do: Jido.Chat.Schema.parse!(__MODULE__, @schema, attrs)

  @doc "Returns a default accepted response."
  @spec accepted(map() | nil) :: t()
  def accepted(body \\ nil), do: new(%{status: 200, body: body || %{ok: true}})

  @doc "Returns an error response envelope."
  @spec error(integer(), map() | String.t() | nil) :: t()
  def error(status, body \\ nil) when is_integer(status) do
    body =
      cond do
        is_map(body) -> body
        is_binary(body) -> %{error: body}
        true -> %{error: "request_failed"}
      end

    new(%{status: status, body: body})
  end

  @doc "Serializes webhook response into plain map with type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = response) do
    response
    |> Map.from_struct()
    |> Wire.to_plain()
    |> Map.put("__type__", "webhook_response")
  end

  @doc "Builds webhook response from serialized data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: new(map)
end
