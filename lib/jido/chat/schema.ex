defmodule Jido.Chat.Schema do
  @moduledoc false

  alias Jido.Chat.Errors
  alias Jido.Chat.Errors.Validation

  @spec put_default(map(), atom(), term()) :: map()
  def put_default(attrs, key, value) do
    if Map.has_key?(attrs, Atom.to_string(key)), do: attrs, else: Map.put_new(attrs, key, value)
  end

  # Normalize declared fields before constructors add defaults or update values.
  # Keep nested maps and unknown keys intact, and reject collisions in the input.
  @spec normalize_keys!(map(), module()) :: map()
  def normalize_keys!(attrs, subject) do
    subject
    |> struct()
    |> Map.from_struct()
    |> Map.keys()
    |> Enum.reduce(attrs, fn key, normalized ->
      string_key = Atom.to_string(key)

      case Map.fetch(attrs, string_key) do
        :error ->
          normalized

        {:ok, value} ->
          if Map.has_key?(attrs, key) do
            raise validation_error(subject, attrs, [Zoi.Error.key_collision(key)])
          end

          normalized |> Map.delete(string_key) |> Map.put(key, value)
      end
    end)
  end

  @spec parse(subject :: term(), schema :: Zoi.schema(), attrs :: map(), keyword()) ::
          {:ok, term()} | {:error, Exception.t()}
  def parse(subject, schema, attrs, opts \\ []) when is_map(attrs) do
    opts = Keyword.put_new(opts, :coerce, true)

    case Zoi.parse(schema, attrs, opts) do
      {:ok, value} ->
        {:ok, value}

      {:error, errors} ->
        {:error, validation_error(subject, attrs, errors)}
    end
  end

  @spec parse!(subject :: term(), schema :: Zoi.schema(), attrs :: map(), keyword()) :: term()
  def parse!(subject, schema, attrs, opts \\ []) when is_map(attrs) do
    case parse(subject, schema, attrs, opts) do
      {:ok, value} -> value
      {:error, error} -> raise error
    end
  end

  defp validation_error(subject, attrs, errors) do
    Errors.to_error(%Validation{subject: subject, input: attrs, errors: errors})
  end
end
