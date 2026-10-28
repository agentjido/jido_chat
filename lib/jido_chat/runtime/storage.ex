defmodule Jido.Chat.Runtime.Storage do
  @moduledoc """
  Small capability contracts for Runtime domain storage.

  A storage selection is `{adapter_module, resource}`. The host starts and owns
  the resource. Jido Chat does not start storage during application startup.
  """

  @type selection :: {module(), term()}

  @doc "Validates a storage selection and its required capabilities."
  @spec validate(selection(), [module()]) :: :ok | {:error, term()}
  def validate({adapter, _resource}, capabilities) when is_atom(adapter) and is_list(capabilities) do
    with {:module, _} <- Code.ensure_compiled(adapter),
         true <- Enum.all?(capabilities, &supports?(adapter, &1)) do
      :ok
    else
      _ -> {:error, :unsupported_storage_capability}
    end
  end

  def validate(_, _), do: {:error, :invalid_storage}

  @doc "Returns true when an adapter implements one storage capability."
  @spec supports?(module(), module()) :: boolean()
  def supports?(adapter, capability) do
    capability.behaviour_info(:callbacks)
    |> Enum.all?(fn {name, arity} -> function_exported?(adapter, name, arity) end)
  end
end
