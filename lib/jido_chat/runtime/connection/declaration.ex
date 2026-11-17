defmodule Jido.Chat.Runtime.Connection.Declaration do
  @moduledoc "Durable desired state and credential references for one provider account Agent."

  alias Jido.Chat.Runtime.Data

  @fields [
    :schema_version,
    :account_id,
    :definition_key,
    :desired,
    :secret_refs,
    :settings,
    :metadata,
    :revision,
    :inserted_at,
    :updated_at
  ]
  @update_fields [:secret_refs, :settings, :metadata]
  @desired [:running, :stopped]

  @enforce_keys @fields
  defstruct @fields

  @type desired :: :running | :stopped
  @type t :: %__MODULE__{
          schema_version: 1,
          account_id: String.t(),
          definition_key: String.t(),
          desired: desired(),
          secret_refs: %{optional(String.t()) => String.t()},
          settings: map(),
          metadata: map(),
          revision: pos_integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @doc "Builds one validated durable provider account declaration."
  @spec new(t() | map()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = declaration), do: declaration |> Map.from_struct() |> new()

  def new(attrs) when is_map(attrs) do
    now = DateTime.utc_now()

    with attrs <- atomize(attrs, @fields),
         true <- Map.keys(attrs) -- @fields == [],
         attrs <- normalize_desired(attrs),
         {:ok, secret_refs} <- secret_refs(Map.get(attrs, :secret_refs, %{})),
         {:ok, settings} <- Data.portable_map(Map.get(attrs, :settings, %{}), :invalid_connection_settings),
         {:ok, metadata} <- Data.portable_map(Map.get(attrs, :metadata, %{}), :invalid_connection_metadata),
         {:ok, inserted_at} <- Data.datetime(Map.get(attrs, :inserted_at, now)),
         {:ok, updated_at} <- Data.datetime(Map.get(attrs, :updated_at, now)) do
      attrs =
        attrs
        |> Map.put_new(:schema_version, 1)
        |> Map.put_new(:desired, :running)
        |> Map.put(:secret_refs, secret_refs)
        |> Map.put(:settings, settings)
        |> Map.put(:metadata, metadata)
        |> Map.put_new(:revision, 1)
        |> Map.put(:inserted_at, inserted_at)
        |> Map.put(:updated_at, updated_at)

      attrs |> then(&struct(__MODULE__, &1)) |> validate()
    else
      false -> {:error, :invalid_connection_declaration}
      {:error, _reason} = error -> error
    end
  end

  def new(_value), do: {:error, :invalid_connection_declaration}

  @doc "Builds one declaration or raises."
  @spec new!(t() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, declaration} -> declaration
      {:error, reason} -> raise ArgumentError, "invalid connection declaration: #{inspect(reason)}"
    end
  end

  @doc "Builds the next desired-state revision."
  @spec set_desired(t(), desired()) :: {:ok, t()} | {:error, term()}
  def set_desired(%__MODULE__{desired: desired} = declaration, desired), do: {:ok, declaration}

  def set_desired(%__MODULE__{} = declaration, desired) when desired in @desired do
    declaration
    |> Map.from_struct()
    |> Map.merge(%{
      desired: desired,
      revision: declaration.revision + 1,
      updated_at: DateTime.utc_now()
    })
    |> new()
  end

  def set_desired(_declaration, _desired), do: {:error, :invalid_connection_declaration}

  @doc "Builds the next configuration revision."
  @spec update(t(), map()) :: {:ok, t()} | {:error, term()}
  def update(%__MODULE__{} = declaration, attrs) when is_map(attrs) do
    attrs = atomize(attrs, @update_fields)

    cond do
      map_size(attrs) == 0 or Map.keys(attrs) -- @update_fields != [] ->
        {:error, :invalid_connection_update}

      true ->
        candidate = Map.merge(Map.from_struct(declaration), attrs)

        with {:ok, next} <- new(candidate) do
          if same_configuration?(declaration, next) do
            {:ok, declaration}
          else
            next
            |> Map.from_struct()
            |> Map.merge(%{
              revision: declaration.revision + 1,
              updated_at: DateTime.utc_now()
            })
            |> new()
          end
        end
    end
  end

  def update(_declaration, _attrs), do: {:error, :invalid_connection_update}

  @doc "Serializes a declaration without resolved credentials."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = declaration) do
    %{
      "__type__" => "runtime_connection_declaration",
      "schema_version" => declaration.schema_version,
      "account_id" => declaration.account_id,
      "definition_key" => declaration.definition_key,
      "desired" => Atom.to_string(declaration.desired),
      "secret_refs" => declaration.secret_refs,
      "settings" => declaration.settings,
      "metadata" => declaration.metadata,
      "revision" => declaration.revision,
      "inserted_at" => DateTime.to_iso8601(declaration.inserted_at),
      "updated_at" => DateTime.to_iso8601(declaration.updated_at)
    }
  end

  @doc "Restores a declaration from a portable map."
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()
  def from_map(_value), do: {:error, :invalid_connection_declaration}

  defp validate(%__MODULE__{} = value) do
    valid =
      value.schema_version == 1 and Data.valid_id?(value.account_id) and
        Data.valid_id?(value.definition_key) and value.desired in @desired and
        valid_secret_refs?(value.secret_refs) and is_map(value.settings) and is_map(value.metadata) and
        is_integer(value.revision) and value.revision > 0 and Data.utc?(value.inserted_at) and
        Data.utc?(value.updated_at) and DateTime.compare(value.updated_at, value.inserted_at) in [:eq, :gt]

    if valid, do: {:ok, value}, else: {:error, :invalid_connection_declaration}
  end

  defp secret_refs(value) do
    with {:ok, value} <- Data.portable_map(value, :invalid_secret_refs),
         true <- valid_secret_refs?(value) do
      {:ok, value}
    else
      _reason -> {:error, :invalid_secret_refs}
    end
  end

  defp valid_secret_refs?(value) when is_map(value) do
    Enum.all?(value, fn {key, reference} ->
      Data.valid_id?(key) and is_binary(reference) and byte_size(reference) in 1..2_048
    end)
  end

  defp valid_secret_refs?(_value), do: false

  defp same_configuration?(left, right) do
    left.secret_refs == right.secret_refs and left.settings == right.settings and
      left.metadata == right.metadata
  end

  defp normalize_desired(attrs) do
    case Map.get(attrs, :desired) do
      value when is_binary(value) ->
        case Enum.find(@desired, &(Atom.to_string(&1) == value)) do
          nil -> attrs
          desired -> Map.put(attrs, :desired, desired)
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
