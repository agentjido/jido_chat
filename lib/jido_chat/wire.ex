defmodule Jido.Chat.Wire do
  @moduledoc false

  @spec to_plain(term()) :: term()
  def to_plain(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def to_plain(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  def to_plain(%MapSet{} = value), do: value |> Enum.to_list() |> Enum.map(&to_plain/1)

  def to_plain(%Regex{} = value) do
    %{"source" => value.source, "opts" => Regex.opts(value)}
  end

  def to_plain(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> to_plain()
  end

  def to_plain(map) when is_map(map) do
    map
    |> Enum.reject(fn {key, _value} -> key == :__struct__ or key == "__struct__" end)
    |> Enum.map(fn {key, value} -> {normalize_key(key), to_plain(value)} end)
    |> Map.new()
  end

  def to_plain(list) when is_list(list), do: Enum.map(list, &to_plain/1)
  def to_plain(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&to_plain/1)
  def to_plain(value), do: value

  @spec encode_module(module() | atom() | nil) :: String.t() | nil
  def encode_module(nil), do: nil
  def encode_module(module) when is_atom(module), do: Atom.to_string(module)

  @spec decode_module(module() | String.t() | nil) :: module() | nil
  def decode_module(nil), do: nil
  def decode_module(module) when is_atom(module), do: module

  def decode_module(module_name) when is_binary(module_name) do
    module =
      module_name
      |> String.trim_leading("Elixir.")
      |> String.split(".")
      |> Module.concat()

    module
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: key
end
