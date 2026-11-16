defmodule Jido.Chat.IdentityProvider do
  @moduledoc """
  Resolves an external identity source through a host identity system.

  Implementations must return a `Jido.Chat.Principal`. They must not return
  credentials, tokens, or reusable proof material.
  """

  alias Jido.Chat.{IdentitySource, Principal}

  @callback resolve(IdentitySource.t(), map()) :: {:ok, Principal.t() | map()} | {:error, atom()}

  @doc "Returns true when a module implements the identity provider contract."
  @spec valid?(term()) :: boolean()
  def valid?(module) when is_atom(module) and module not in [nil, true, false] do
    match?({:module, _}, Code.ensure_compiled(module)) and function_exported?(module, :resolve, 2)
  end

  def valid?(_module), do: false

  @doc "Invokes one provider and validates its Principal result."
  @spec resolve(module(), IdentitySource.t(), map()) :: {:ok, Principal.t()} | {:error, term()}
  def resolve(provider, %IdentitySource{} = source, context) when is_map(context) do
    if valid?(provider) do
      case provider.resolve(source, context) do
        {:ok, %Principal{} = principal} -> validate_principal(principal)
        {:ok, principal} when is_map(principal) -> validate_principal(principal)
        {:error, reason} when is_atom(reason) -> {:error, reason}
        {:error, _reason} -> {:error, :identity_not_resolved}
        _other -> {:error, :invalid_identity_provider_result}
      end
    else
      {:error, :invalid_identity_provider}
    end
  rescue
    _ -> {:error, :identity_provider_failed}
  catch
    _, _ -> {:error, :identity_provider_failed}
  end

  def resolve(_provider, _source, _context), do: {:error, :invalid_identity_request}

  defp validate_principal(value) do
    {:ok, Principal.new(value)}
  rescue
    _ -> {:error, :invalid_principal}
  end
end
