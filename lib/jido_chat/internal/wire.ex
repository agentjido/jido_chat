defmodule Jido.Chat.Wire do
  @moduledoc false

  @doc false
  @spec portable(term(), keyword()) :: :ok | {:error, String.t()}
  def portable(value, _opts) do
    with :ok <- unique_wire_keys(value),
         {:ok, _encoded} <- value |> to_plain() |> Jason.encode() do
      :ok
    else
      _ -> {:error, "expected a portable JSON value"}
    end
  rescue
    _ -> {:error, "expected a portable JSON value"}
  catch
    _, _ -> {:error, "expected a portable JSON value"}
  end

  @spec to_plain(term()) :: term()
  def to_plain(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def to_plain(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  def to_plain(%MapSet{} = value), do: Enum.map(value, &to_plain/1)

  def to_plain(%Regex{} = value) do
    %{"source" => value.source, "opts" => Regex.opts(value)}
  end

  def to_plain(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> to_plain()
  end

  def to_plain(map) when is_map(map) do
    Map.new(Map.drop(map, [:__struct__, "__struct__"]), fn {key, value} ->
      {normalize_key(key), to_plain(value)}
    end)
  end

  def to_plain(list) when is_list(list), do: Enum.map(list, &to_plain/1)
  def to_plain(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&to_plain/1)
  def to_plain(value) when is_atom(value) and value not in [nil, true, false], do: Atom.to_string(value)
  def to_plain(value), do: value

  defp unique_wire_keys(%DateTime{}), do: :ok
  defp unique_wire_keys(%NaiveDateTime{}), do: :ok
  defp unique_wire_keys(%Regex{}), do: :ok

  defp unique_wire_keys(%MapSet{} = value), do: unique_wire_keys(MapSet.to_list(value))

  defp unique_wire_keys(%_{} = struct), do: unique_wire_keys(Map.from_struct(struct))

  defp unique_wire_keys(map) when is_map(map) do
    with {:ok, keys} <- wire_keys(map),
         true <- length(keys) == length(Enum.uniq(keys)) do
      validate_values(map)
    else
      false -> {:error, :portable_key_collision}
      error -> error
    end
  end

  defp unique_wire_keys(list) when is_list(list) do
    Enum.reduce_while(list, :ok, fn value, :ok ->
      case unique_wire_keys(value) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp unique_wire_keys(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> unique_wire_keys()

  defp unique_wire_keys(_value), do: :ok

  defp wire_keys(map) do
    Enum.reduce_while(map, {:ok, []}, fn {key, _value}, {:ok, keys} ->
      case wire_key(key) do
        {:ok, key} -> {:cont, {:ok, [key | keys]}}
        error -> {:halt, error}
      end
    end)
  end

  defp wire_key(key) when is_binary(key), do: {:ok, key}
  defp wire_key(key) when is_atom(key), do: {:ok, Atom.to_string(key)}
  defp wire_key(_key), do: {:error, :portable_key_type}

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: key

  defp validate_values(map) do
    Enum.reduce_while(map, :ok, fn {_key, value}, :ok ->
      case unique_wire_keys(value) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
end
