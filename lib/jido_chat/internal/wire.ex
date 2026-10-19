defmodule Jido.Chat.Wire do
  @moduledoc false

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

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: key
end
