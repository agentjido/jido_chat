defmodule Jido.Chat.CapabilityMatrix do
  @moduledoc """
  Adapter capability declaration matrix (`:native | :fallback | :unsupported`).
  """

  alias Jido.Chat.Wire

  @statuses [:native, :fallback, :unsupported]

  @schema Zoi.struct(
            __MODULE__,
            %{
              adapter_name: Zoi.atom() |> Zoi.nullish(),
              capabilities: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type capability_status :: :native | :fallback | :unsupported
  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for CapabilityMatrix."
  def schema, do: @schema

  @doc "Creates normalized capability matrix payload."
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    capabilities =
      attrs[:capabilities] || attrs["capabilities"] || attrs[:matrix] || attrs["matrix"] || %{}

    attrs
    |> Map.put(:capabilities, normalize_capabilities(capabilities))
    |> Map.delete("capabilities")
    |> Map.delete(:matrix)
    |> Map.delete("matrix")
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Returns capability matrix map."
  @spec as_map(t()) :: %{optional(atom()) => capability_status()}
  def as_map(%__MODULE__{} = matrix), do: matrix.capabilities

  @doc "Returns declared support status for capability."
  @spec status(t(), atom()) :: capability_status()
  def status(%__MODULE__{} = matrix, capability) when is_atom(capability) do
    Map.get(matrix.capabilities, capability, :unsupported)
  end

  @doc "Serializes capability matrix into plain map with type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = matrix) do
    matrix
    |> Map.from_struct()
    |> Wire.to_plain()
    |> Map.put("__type__", "capability_matrix")
  end

  @doc "Builds capability matrix from serialized map."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: new(map)

  defp normalize_capabilities(capabilities) when is_map(capabilities) do
    capabilities
    |> Enum.map(fn {capability, status} ->
      {normalize_capability_key(capability), normalize_status(status)}
    end)
    |> Map.new()
  end

  defp normalize_capabilities(capabilities) when is_list(capabilities) do
    capabilities
    |> Enum.map(fn capability ->
      {normalize_capability_key(capability), :native}
    end)
    |> Map.new()
  end

  defp normalize_capabilities(_), do: %{}

  defp normalize_capability_key(capability) when is_atom(capability), do: capability

  defp normalize_capability_key(capability) when is_binary(capability) do
    capability
    |> String.trim()
    |> String.to_atom()
  end

  defp normalize_capability_key(capability), do: capability

  defp normalize_status(status) when status in @statuses, do: status

  defp normalize_status(status) when is_binary(status) do
    status
    |> String.trim()
    |> String.to_atom()
    |> normalize_status()
  rescue
    _ -> :unsupported
  end

  defp normalize_status(_), do: :unsupported
end
