defmodule Jido.Chat.Authorizer do
  @moduledoc """
  Authorizes one Chat action at its exact resource.

  A host authorizer can call an existing policy system. Chat does not store or
  interpret organization-wide grants.
  """

  alias Jido.Chat.Principal

  @callback authorize(Principal.t(), atom(), map(), map()) :: :ok | {:error, atom()}

  @doc "Returns true when a module implements the authorizer contract."
  @spec valid?(term()) :: boolean()
  def valid?(module) when is_atom(module) and module not in [nil, true, false] do
    match?({:module, _}, Code.ensure_compiled(module)) and function_exported?(module, :authorize, 4)
  end

  def valid?(_module), do: false

  @doc "Invokes one authorizer and fails closed on invalid results or failures."
  @spec authorize(module(), Principal.t(), atom(), map(), map()) :: :ok | {:error, term()}
  def authorize(authorizer, %Principal{} = principal, action, resource, context)
      when is_atom(action) and is_map(resource) and is_map(context) do
    if valid?(authorizer) do
      case authorizer.authorize(principal, action, resource, context) do
        :ok -> :ok
        {:error, reason} when is_atom(reason) -> {:error, reason}
        {:error, _reason} -> {:error, :authorization_denied}
        _other -> {:error, :invalid_authorizer_result}
      end
    else
      {:error, :invalid_authorizer}
    end
  rescue
    _ -> {:error, :authorizer_failed}
  catch
    _, _ -> {:error, :authorizer_failed}
  end

  def authorize(_authorizer, _principal, _action, _resource, _context),
    do: {:error, :invalid_authorization_request}
end
