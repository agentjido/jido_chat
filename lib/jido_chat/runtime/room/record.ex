defmodule Jido.Chat.Runtime.Room.Record do
  @moduledoc """
  Durable descriptive data for one Runtime Room.

  A record is not an Agent snapshot or managed-process status. It contains no
  membership, message history, credentials, or provider binding data.
  """

  @kinds [:direct, :group, :channel, :thread]
  @fields [:schema_version, :id, :kind, :name, :metadata, :revision, :inserted_at, :updated_at]
  @update_fields [:name, :metadata]
  @max_id_bytes 256

  @schema Zoi.struct(
            __MODULE__,
            %{
              schema_version: Zoi.integer() |> Zoi.min(1) |> Zoi.max(1) |> Zoi.default(1),
              id:
                Zoi.string()
                |> Zoi.min(1)
                |> Zoi.refine({__MODULE__, :valid_id, []}),
              kind: Zoi.enum(@kinds),
              name: Zoi.string() |> Zoi.max(256) |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{}),
              revision: Zoi.integer() |> Zoi.min(1) |> Zoi.default(1),
              inserted_at: Zoi.struct(DateTime),
              updated_at: Zoi.struct(DateTime)
            },
            coerce: true
          )
          |> Zoi.refine({__MODULE__, :valid_record, []})

  @type kind :: :direct | :group | :channel | :thread
  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the durable Room record schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Returns the supported Room kinds."
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc "Builds a validated Room record."
  @spec new(t() | map()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = record), do: record |> Map.from_struct() |> new()

  def new(attrs) when is_map(attrs) do
    now = DateTime.utc_now()

    with :ok <- validate_raw_input(attrs, :invalid_room_record),
         attrs =
           attrs
           |> Map.drop(["__type__", :__type__])
           |> normalize_keys(@fields)
           |> normalize_enum(:kind, @kinds)
           |> normalize_datetime(:inserted_at)
           |> normalize_datetime(:updated_at)
           |> Map.put_new(:schema_version, 1)
           |> Map.put_new(:id, "room/" <> Jido.Id.uuid7())
           |> Map.put_new(:revision, 1)
           |> Map.put_new(:inserted_at, now)
           |> Map.put_new(:updated_at, now),
         {:ok, metadata} <- normalize_metadata(Map.get(attrs, :metadata, %{})),
         {:ok, record} <- parse(Map.put(attrs, :metadata, metadata)) do
      {:ok, record}
    end
  end

  @doc "Builds a validated Room record or raises a validation error."
  @spec new!(t() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, record} -> record
      {:error, %_{} = error} -> raise error
      {:error, reason} -> raise ArgumentError, "invalid Room record: #{inspect(reason)}"
    end
  end

  @doc "Builds the next revision with a changed name or metadata."
  @spec update(t(), map()) :: {:ok, t()} | {:error, term()}
  def update(%__MODULE__{} = record, attrs) when is_map(attrs) do
    with :ok <- validate_raw_input(attrs, :invalid_room_update) do
      attrs =
        attrs
        |> Map.drop(["__type__", :__type__])
        |> normalize_keys(@update_fields)

      cond do
        map_size(attrs) == 0 ->
          {:error, :invalid_room_update}

        Map.keys(attrs) -- @update_fields != [] ->
          {:error, :invalid_room_update}

        true ->
          record
          |> Map.from_struct()
          |> Map.merge(attrs)
          |> Map.put(:revision, record.revision + 1)
          |> Map.put(:updated_at, DateTime.utc_now())
          |> new()
      end
    end
  end

  @doc "Serializes a Room record to a portable map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = record) do
    %{
      "__type__" => "runtime_room_record",
      "schema_version" => record.schema_version,
      "id" => record.id,
      "kind" => Atom.to_string(record.kind),
      "name" => record.name,
      "metadata" => record.metadata,
      "revision" => record.revision,
      "inserted_at" => DateTime.to_iso8601(record.inserted_at),
      "updated_at" => DateTime.to_iso8601(record.updated_at)
    }
  end

  @doc "Restores a Room record from a portable map."
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(map) when is_map(map), do: new(map)

  @doc false
  def valid_id(value, _opts) do
    if is_binary(value) and byte_size(value) in 1..@max_id_bytes,
      do: :ok,
      else: {:error, "id must contain 1 to 256 bytes"}
  end

  @doc false
  def valid_record(%__MODULE__{} = record, _opts) do
    cond do
      not utc?(record.inserted_at) or not utc?(record.updated_at) ->
        {:error, "timestamps must use UTC"}

      DateTime.compare(record.updated_at, record.inserted_at) == :lt ->
        {:error, "updated_at must not precede inserted_at"}

      true ->
        :ok
    end
  end

  defp parse(attrs) do
    case Zoi.parse(@schema, attrs, coerce: true) do
      {:ok, record} ->
        {:ok, record}

      {:error, errors} ->
        {:error,
         Jido.Chat.Errors.to_error(%Jido.Chat.Errors.Validation{
           subject: __MODULE__,
           errors: errors
         })}
    end
  end

  defp validate_raw_input(value, reason) do
    if raw_input?(value), do: :ok, else: {:error, reason}
  end

  defp raw_input?(value)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value) or
              is_atom(value),
       do: true

  defp raw_input?(values) when is_list(values), do: Enum.all?(values, &raw_input?/1)

  defp raw_input?(values) when is_tuple(values),
    do: values |> Tuple.to_list() |> Enum.all?(&raw_input?/1)

  defp raw_input?(value) when is_map(value) do
    keys = Enum.map(Map.keys(value), &raw_input_key/1)

    Enum.all?(keys, &is_binary/1) and length(keys) == length(Enum.uniq(keys)) and
      Enum.all?(Map.values(value), &raw_input?/1)
  end

  defp raw_input?(_value), do: false

  defp raw_input_key(key) when is_binary(key), do: key
  defp raw_input_key(key) when is_atom(key), do: Atom.to_string(key)
  defp raw_input_key(_key), do: nil

  defp normalize_keys(attrs, keys) do
    Enum.reduce(keys, attrs, fn key, acc ->
      string_key = Atom.to_string(key)

      if Map.has_key?(acc, string_key) and not Map.has_key?(acc, key) do
        acc |> Map.put(key, Map.fetch!(acc, string_key)) |> Map.delete(string_key)
      else
        Map.delete(acc, string_key)
      end
    end)
  end

  defp normalize_enum(attrs, key, allowed) do
    case Map.get(attrs, key) do
      value when is_binary(value) ->
        case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
          nil -> attrs
          atom -> Map.put(attrs, key, atom)
        end

      _value ->
        attrs
    end
  end

  defp normalize_metadata(value), do: normalize_metadata(value, 0)

  defp normalize_metadata(_value, depth) when depth > 16,
    do: {:error, :invalid_room_metadata}

  defp normalize_metadata(value, _depth)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value),
       do: {:ok, value}

  defp normalize_metadata(value, _depth) when is_atom(value),
    do: {:ok, Atom.to_string(value)}

  defp normalize_metadata(values, depth) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, items} ->
      case normalize_metadata(value, depth + 1) do
        {:ok, value} -> {:cont, {:ok, [value | items]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp normalize_metadata(value, depth) when is_map(value) and not is_struct(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, item}, {:ok, items} ->
      with {:ok, key} <- metadata_key(key),
           false <- Map.has_key?(items, key),
           {:ok, item} <- normalize_metadata(item, depth + 1) do
        {:cont, {:ok, Map.put(items, key, item)}}
      else
        _reason -> {:halt, {:error, :invalid_room_metadata}}
      end
    end)
  end

  defp normalize_metadata(_value, _depth), do: {:error, :invalid_room_metadata}

  defp metadata_key(key) when is_binary(key) and key != "", do: {:ok, key}
  defp metadata_key(key) when is_atom(key), do: {:ok, Atom.to_string(key)}
  defp metadata_key(_key), do: {:error, :invalid_room_metadata}

  defp normalize_datetime(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, 0} -> Map.put(attrs, key, datetime)
          _other -> attrs
        end

      _value ->
        attrs
    end
  end

  defp utc?(%DateTime{utc_offset: 0, std_offset: 0}), do: true
  defp utc?(_value), do: false
end
