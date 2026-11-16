defmodule Jido.Chat.Value do
  @moduledoc false

  alias Jido.Chat.Errors.Validation

  @doc false
  @spec normalize_keys(map(), [atom()]) :: map()
  def normalize_keys(attrs, keys) when is_map(attrs) do
    Enum.reduce(keys, attrs, fn key, acc ->
      string_key = Atom.to_string(key)

      if Map.has_key?(acc, string_key) and not Map.has_key?(acc, key) do
        acc |> Map.put(key, Map.fetch!(acc, string_key)) |> Map.delete(string_key)
      else
        Map.delete(acc, string_key)
      end
    end)
  end

  @doc false
  @spec normalize_enum(map(), atom(), [atom()]) :: map()
  def normalize_enum(attrs, key, allowed) do
    case Map.get(attrs, key) do
      value when is_binary(value) ->
        case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
          nil -> attrs
          atom -> Map.put(attrs, key, atom)
        end

      _ ->
        attrs
    end
  end

  @doc false
  @spec plain_struct(struct(), String.t(), map()) :: map()
  def plain_struct(struct, marker, replacements \\ %{}) do
    struct
    |> Map.from_struct()
    |> Map.merge(replacements)
    |> Jido.Chat.Wire.to_plain()
    |> Map.put("__type__", marker)
  end

  @doc false
  @spec validate_portable!(map()) :: map()
  def validate_portable!(map) do
    case Jido.Chat.Wire.portable(map, []) do
      :ok -> map
      {:error, message} -> raise Validation, subject: "data", errors: [%{message: message}]
    end
  end

  @doc false
  @spec without_marker(map()) :: map()
  def without_marker(map) do
    map
    |> validate_portable!()
    |> Map.drop(["__type__", :__type__])
  end
end
