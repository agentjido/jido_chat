defmodule Jido.Chat.Runtime.Bridge.Binding do
  @moduledoc "Durable mapping between one provider Room and one local Runtime Room."

  alias Jido.Chat.Runtime.Data

  @fields [
    :schema_version,
    :account_id,
    :room_id,
    :external_room_id,
    :direction,
    :enabled,
    :metadata,
    :revision,
    :inserted_at,
    :updated_at
  ]
  @update_fields [:room_id, :direction, :enabled, :metadata]
  @directions [:inbound, :outbound, :both]

  @enforce_keys @fields
  defstruct @fields

  @type direction :: :inbound | :outbound | :both
  @type t :: %__MODULE__{
          schema_version: 1,
          account_id: String.t(),
          room_id: String.t(),
          external_room_id: String.t(),
          direction: direction(),
          enabled: boolean(),
          metadata: map(),
          revision: pos_integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @doc "Returns the supported bridge directions."
  @spec directions() :: [direction()]
  def directions, do: @directions

  @doc "Builds one validated durable bridge binding."
  @spec new(t() | map()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = binding), do: binding |> Map.from_struct() |> new()

  def new(attrs) when is_map(attrs) do
    now = DateTime.utc_now()

    with attrs <- atomize(attrs, @fields),
         true <- Map.keys(attrs) -- @fields == [],
         attrs <- normalize_direction(attrs),
         {:ok, metadata} <- Data.portable_map(Map.get(attrs, :metadata, %{}), :invalid_binding_metadata),
         {:ok, inserted_at} <- Data.datetime(Map.get(attrs, :inserted_at, now)),
         {:ok, updated_at} <- Data.datetime(Map.get(attrs, :updated_at, now)) do
      attrs =
        attrs
        |> Map.put_new(:schema_version, 1)
        |> Map.put_new(:direction, :both)
        |> Map.put_new(:enabled, true)
        |> Map.put(:metadata, metadata)
        |> Map.put_new(:revision, 1)
        |> Map.put(:inserted_at, inserted_at)
        |> Map.put(:updated_at, updated_at)

      attrs |> then(&struct(__MODULE__, &1)) |> validate()
    else
      false -> {:error, :invalid_bridge_binding}
      {:error, _reason} = error -> error
    end
  end

  def new(_value), do: {:error, :invalid_bridge_binding}

  @doc "Builds one binding or raises."
  @spec new!(t() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, binding} -> binding
      {:error, reason} -> raise ArgumentError, "invalid bridge binding: #{inspect(reason)}"
    end
  end

  @doc "Builds the next binding revision."
  @spec update(t(), map()) :: {:ok, t()} | {:error, term()}
  def update(%__MODULE__{} = binding, attrs) when is_map(attrs) do
    attrs = atomize(attrs, @update_fields)

    cond do
      map_size(attrs) == 0 or Map.keys(attrs) -- @update_fields != [] ->
        {:error, :invalid_binding_update}

      true ->
        candidate = Map.merge(Map.from_struct(binding), attrs)

        with {:ok, next} <- new(candidate) do
          if same_configuration?(binding, next) do
            {:ok, binding}
          else
            next
            |> Map.from_struct()
            |> Map.merge(%{revision: binding.revision + 1, updated_at: DateTime.utc_now()})
            |> new()
          end
        end
    end
  end

  def update(_binding, _attrs), do: {:error, :invalid_binding_update}

  @doc "Builds the next enabled-state revision."
  @spec set_enabled(t(), boolean()) :: {:ok, t()} | {:error, term()}
  def set_enabled(%__MODULE__{enabled: enabled} = binding, enabled), do: {:ok, binding}
  def set_enabled(%__MODULE__{} = binding, enabled) when is_boolean(enabled), do: update(binding, %{enabled: enabled})
  def set_enabled(_binding, _enabled), do: {:error, :invalid_binding_update}

  @doc "Returns a stable runtime mapping name without creating an atom."
  @spec mapping_name(t()) :: String.t()
  def mapping_name(%__MODULE__{} = binding) do
    data = :erlang.term_to_binary({binding.account_id, binding.external_room_id}, [:deterministic])
    "binding/" <> Base.url_encode64(:crypto.hash(:sha256, data), padding: false)
  end

  @doc "Serializes a binding to a portable map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = binding) do
    %{
      "__type__" => "runtime_bridge_binding",
      "schema_version" => binding.schema_version,
      "account_id" => binding.account_id,
      "room_id" => binding.room_id,
      "external_room_id" => binding.external_room_id,
      "direction" => Atom.to_string(binding.direction),
      "enabled" => binding.enabled,
      "metadata" => binding.metadata,
      "revision" => binding.revision,
      "inserted_at" => DateTime.to_iso8601(binding.inserted_at),
      "updated_at" => DateTime.to_iso8601(binding.updated_at)
    }
  end

  @doc "Restores a binding from a portable map."
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()
  def from_map(_value), do: {:error, :invalid_bridge_binding}

  defp validate(%__MODULE__{} = value) do
    valid =
      value.schema_version == 1 and Data.valid_id?(value.account_id) and Data.valid_id?(value.room_id) and
        Data.valid_id?(value.external_room_id) and value.direction in @directions and
        is_boolean(value.enabled) and is_map(value.metadata) and is_integer(value.revision) and
        value.revision > 0 and Data.utc?(value.inserted_at) and Data.utc?(value.updated_at) and
        DateTime.compare(value.updated_at, value.inserted_at) in [:eq, :gt]

    if valid, do: {:ok, value}, else: {:error, :invalid_bridge_binding}
  end

  defp same_configuration?(left, right) do
    left.room_id == right.room_id and left.direction == right.direction and
      left.enabled == right.enabled and left.metadata == right.metadata
  end

  defp normalize_direction(attrs) do
    case Map.get(attrs, :direction) do
      value when is_binary(value) ->
        case Enum.find(@directions, &(Atom.to_string(&1) == value)) do
          nil -> attrs
          direction -> Map.put(attrs, :direction, direction)
        end

      _value ->
        attrs
    end
  end

  defp atomize(attrs, fields) do
    Enum.reduce(fields, attrs, fn field, result ->
      string = Atom.to_string(field)

      if Map.has_key?(result, string) and not Map.has_key?(result, field) do
        result |> Map.put(field, Map.fetch!(result, string)) |> Map.delete(string)
      else
        Map.delete(result, string)
      end
    end)
  end
end
