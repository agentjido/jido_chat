defmodule Jido.Chat.RequestStore do
  @moduledoc false
  alias Jido.Chat.Signal.Policy
  @backend_key {__MODULE__, :backend}

  # Installation is private and precedes publication of a new, owned binding.
  # It does not add an adapter option or change a live external binding.
  def install(binding, {module, reference}) do
    if :ets.info(binding.resources, :owner) == self() and :ets.info(binding.resources, :size) == 0 do
      true = :ets.insert_new(binding.resources, {@backend_key, {module, reference}})
      :ok
    else
      Policy.error(:invalid_binding)
    end
  rescue
    ArgumentError -> Policy.error(:invalid_binding)
  end

  def claim(binding, key, digest) do
    case backend(binding) do
      nil ->
        claim_ets(binding, key, digest)

      {module, reference} ->
        case module.claim(reference, key, digest) do
          {:ok, claim} -> {:ok, {:claimed, {:backend, module, reference, claim}}}
          {:cached, result} -> {:ok, {:cached, result}}
          error -> error
        end
    end
  rescue
    ArgumentError -> Policy.error(:invalid_binding)
  end

  def complete(_binding, {:backend, module, reference, claim}, result),
    do: module.complete(reference, claim, result)

  def complete(binding, {:ets, key, digest}, result) do
    :ets.insert(binding.resources, {key, digest, {:done, result}})
    :ok
  rescue
    ArgumentError -> :ok
  end

  def remember(binding, result_id, class, tag) do
    case backend(binding) do
      nil ->
        :ets.insert(binding.resources, {{:failure_class, result_id}, class, tag})
        :ok

      {module, reference} ->
        module.remember(reference, result_id, class, tag)
    end
  end

  def failure(binding, result_id) do
    case backend(binding) do
      nil ->
        case :ets.lookup(binding.resources, {:failure_class, result_id}) do
          [{_key, class, tag}] -> {:ok, {class, tag}}
          [] -> {:error, :not_found}
        end

      {module, reference} ->
        module.failure(reference, result_id)
    end
  end

  defp backend(binding) do
    case :ets.lookup(binding.resources, @backend_key) do
      [{@backend_key, backend}] -> backend
      [] -> nil
    end
  end

  defp claim_ets(binding, key, digest) do
    if :ets.insert_new(binding.resources, {key, digest, {:running, self()}}) do
      {:ok, {:claimed, {:ets, key, digest}}}
    else
      case :ets.lookup(binding.resources, key) do
        [{^key, ^digest, {:done, result}}] ->
          {:ok, {:cached, result}}

        [{^key, ^digest, {:running, owner}}] ->
          Policy.error(if(Process.alive?(owner), do: :request_in_progress, else: :request_outcome_unknown))

        _ ->
          Policy.error(:request_conflict)
      end
    end
  end
end
