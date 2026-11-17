defmodule Jido.Chat.Runtime.Data do
  @moduledoc false

  @max_depth 16

  @doc false
  def portable_map(value, error) when is_map(value) and not is_struct(value) do
    case portable(value, 0) do
      {:ok, normalized} when is_map(normalized) -> {:ok, normalized}
      _other -> {:error, error}
    end
  end

  def portable_map(_value, error), do: {:error, error}

  @doc false
  def datetime(%DateTime{} = value), do: {:ok, value}

  def datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, 0} -> {:ok, datetime}
      _other -> {:error, :invalid_datetime}
    end
  end

  def datetime(_value), do: {:error, :invalid_datetime}

  @doc false
  def utc?(%DateTime{utc_offset: 0, std_offset: 0}), do: true
  def utc?(_value), do: false

  @doc false
  def valid_id?(value, max_bytes \\ 256),
    do: is_binary(value) and byte_size(value) in 1..max_bytes

  defp portable(_value, depth) when depth > @max_depth, do: :error

  defp portable(value, _depth)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value),
       do: {:ok, value}

  defp portable(value, _depth) when is_atom(value), do: {:ok, Atom.to_string(value)}

  defp portable(values, depth) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, items} ->
      case portable(value, depth + 1) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | items]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      :error -> :error
    end
  end

  defp portable(value, depth) when is_map(value) and not is_struct(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, item}, {:ok, items} ->
      with {:ok, key} <- portable_key(key),
           false <- Map.has_key?(items, key),
           {:ok, normalized} <- portable(item, depth + 1) do
        {:cont, {:ok, Map.put(items, key, normalized)}}
      else
        _reason -> {:halt, :error}
      end
    end)
  end

  defp portable(_value, _depth), do: :error

  defp portable_key(key) when is_binary(key) and key != "", do: {:ok, key}
  defp portable_key(key) when is_atom(key), do: {:ok, Atom.to_string(key)}
  defp portable_key(_key), do: :error
end
