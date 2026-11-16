defmodule Jido.Chat.Runtime.Room.Declaration do
  @moduledoc "Durable desired state for one managed Room Agent."

  @fields [:schema_version, :room_id, :definition_key, :desired, :revision, :inserted_at, :updated_at]
  @desired [:running, :stopped]
  @max_bytes 256

  @enforce_keys @fields
  defstruct @fields

  @type desired :: :running | :stopped
  @type t :: %__MODULE__{
          schema_version: 1,
          room_id: String.t(),
          definition_key: String.t(),
          desired: desired(),
          revision: pos_integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @doc "Builds one validated durable Room declaration."
  @spec new(t() | map()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = value), do: validate(value)

  def new(attrs) when is_map(attrs) do
    now = DateTime.utc_now()

    attrs =
      attrs
      |> atomize(@fields)
      |> Map.put_new(:schema_version, 1)
      |> Map.put_new(:desired, :running)
      |> Map.put_new(:revision, 1)
      |> Map.put_new(:inserted_at, now)
      |> Map.put_new(:updated_at, now)

    if Map.keys(attrs) -- @fields == [] do
      attrs |> then(&struct(__MODULE__, &1)) |> validate()
    else
      {:error, :invalid_room_declaration}
    end
  end

  def new(_value), do: {:error, :invalid_room_declaration}

  @doc "Builds one declaration or raises."
  def new!(attrs), do: unwrap!(new(attrs))

  @doc "Builds the next desired-state revision."
  @spec set_desired(t(), desired()) :: {:ok, t()} | {:error, term()}
  def set_desired(%__MODULE__{desired: desired} = value, desired), do: {:ok, value}

  def set_desired(%__MODULE__{} = value, desired) when desired in @desired do
    validate(%{value | desired: desired, revision: value.revision + 1, updated_at: DateTime.utc_now()})
  end

  def set_desired(_value, _desired), do: {:error, :invalid_room_declaration}

  defp validate(%__MODULE__{} = value) do
    valid =
      value.schema_version == 1 and valid_id?(value.room_id) and valid_id?(value.definition_key) and
        value.desired in @desired and is_integer(value.revision) and value.revision > 0 and
        utc?(value.inserted_at) and utc?(value.updated_at) and
        DateTime.compare(value.updated_at, value.inserted_at) in [:eq, :gt]

    if valid, do: {:ok, value}, else: {:error, :invalid_room_declaration}
  end

  defp valid_id?(value),
    do: is_binary(value) and byte_size(value) in 1..@max_bytes

  defp utc?(%DateTime{utc_offset: 0, std_offset: 0}), do: true
  defp utc?(_value), do: false

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

  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, reason}), do: raise(ArgumentError, "invalid Room declaration: #{inspect(reason)}")
end
