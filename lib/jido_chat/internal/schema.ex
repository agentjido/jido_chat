defmodule Jido.Chat.Schema do
  @moduledoc false

  alias Jido.Chat.Errors
  alias Jido.Chat.Errors.Validation

  @spec parse(subject :: term(), schema :: Zoi.schema(), attrs :: map(), keyword()) ::
          {:ok, term()} | {:error, Exception.t()}
  def parse(subject, schema, attrs, opts \\ []) when is_map(attrs) do
    opts = Keyword.put_new(opts, :coerce, true)

    case Zoi.parse(schema, attrs, opts) do
      {:ok, value} -> {:ok, value}
      {:error, errors} -> validation_error(subject, errors)
    end
  end

  @spec parse!(subject :: term(), schema :: Zoi.schema(), attrs :: map(), keyword()) :: term()
  def parse!(subject, schema, attrs, opts \\ []) when is_map(attrs) do
    case parse(subject, schema, attrs, opts) do
      {:ok, value} -> value
      {:error, error} -> raise error
    end
  end

  defp validation_error(subject, errors) do
    {:error,
     Errors.to_error(%Validation{
       subject: subject,
       errors: errors
     })}
  end
end
