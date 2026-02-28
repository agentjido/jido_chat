defmodule Jido.Chat.ModalResult do
  @moduledoc """
  Typed normalized modal-open result.
  """

  alias Jido.Chat.Wire

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              status: Zoi.enum([:opened, :accepted, :failed]) |> Zoi.default(:opened),
              external_room_id: Zoi.any() |> Zoi.nullish(),
              external_message_id: Zoi.string() |> Zoi.nullish(),
              raw: Zoi.any() |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for ModalResult."
  def schema, do: @schema

  @doc "Creates a normalized modal result."
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    attrs
    |> Map.put_new(:id, Jido.Chat.ID.generate!())
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Serializes modal result into plain map with type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = result) do
    result
    |> Map.from_struct()
    |> Wire.to_plain()
    |> Map.put("__type__", "modal_result")
  end

  @doc "Builds modal result from serialized data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: new(map)
end
