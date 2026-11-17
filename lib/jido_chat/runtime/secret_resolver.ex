defmodule Jido.Chat.Runtime.SecretResolver do
  @moduledoc """
  Resolves opaque host secret references for one provider account activation.

  Jido Chat calls the resolver only when it must start an account Agent. The
  returned credentials are put in that Agent in memory and are never stored by
  Runtime storage.
  """

  @type context :: %{
          required(:account_id) => String.t(),
          required(:definition_key) => String.t(),
          required(:settings) => map(),
          required(:metadata) => map()
        }

  @callback resolve(secret_refs :: map(), context()) :: {:ok, map()} | {:error, term()}

  @doc false
  @spec resolve(module() | nil, map(), context()) :: {:ok, map()} | {:error, term()}
  def resolve(_resolver, refs, _context) when map_size(refs) == 0, do: {:ok, %{}}
  def resolve(nil, _refs, _context), do: {:error, :secret_resolver_required}

  def resolve(resolver, refs, context) when is_atom(resolver) and is_map(refs) and is_map(context) do
    with {:module, _module} <- Code.ensure_compiled(resolver),
         true <- function_exported?(resolver, :resolve, 2),
         {:ok, credentials} when is_map(credentials) <- resolver.resolve(refs, context) do
      {:ok, credentials}
    else
      false -> {:error, :invalid_secret_resolver}
      {:error, _reason} -> {:error, :secret_resolution_failed}
      _other -> {:error, :secret_resolution_failed}
    end
  rescue
    _error -> {:error, :secret_resolution_failed}
  catch
    :exit, _reason -> {:error, :secret_resolution_failed}
    _kind, _reason -> {:error, :secret_resolution_failed}
  end

  def resolve(_resolver, _refs, _context), do: {:error, :invalid_secret_resolver}
end
