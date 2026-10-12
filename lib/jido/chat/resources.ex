defmodule Jido.Chat.Resources do
  @moduledoc false

  alias Jido.Chat.Binding
  alias Jido.Chat.Signal.Policy
  @kinds ~w(file media stream card modal result)

  @doc false
  @spec put(Binding.t(), String.t(), term(), keyword()) :: {:ok, map()} | {:error, Jido.Chat.Errors.Contract.t()}
  def put(%Binding{} = binding, kind, value, opts) when is_list(opts) do
    if kind in @kinds and Keyword.keyword?(opts) do
      id = Jido.Chat.ID.generate!()
      ttl = Keyword.get(opts, :ttl_ms, 60_000)

      if is_integer(ttl) and ttl >= 0 do
        :ets.insert(
          binding.resources,
          {{:resource, id}, self(), kind, value, System.monotonic_time(:millisecond) + ttl, :active}
        )

        {:ok, %{"id" => id, "scope" => "call", "binding_id" => binding.id, "kind" => kind}}
      else
        Policy.error(:invalid_resource)
      end
    else
      Policy.error(:invalid_resource)
    end
  rescue
    ArgumentError -> Policy.error(:resource_expired)
  end

  def put(_binding, _kind, _value, _opts), do: Policy.error(:invalid_resource)

  @doc false
  @spec resolve(Binding.t(), map()) :: {:ok, term()} | {:error, Jido.Chat.Errors.Contract.t()}
  def resolve(binding, ref) do
    with {:ok, {_key, _owner, _kind, value, _expiry, :active}} <- entry(binding, ref) do
      {:ok, value}
    end
  end

  @doc false
  @spec cancel(Binding.t(), map()) :: :ok | {:error, Jido.Chat.Errors.Contract.t()}
  def cancel(binding, ref) do
    with {:ok, {key, owner, kind, _value, expiry, :active}} <- entry(binding, ref) do
      :ets.insert(binding.resources, {key, owner, kind, nil, expiry, :cancelled})
      :ok
    end
  end

  @doc false
  @spec fail(Binding.t(), map()) :: :ok | {:error, Jido.Chat.Errors.Contract.t()}
  def fail(binding, ref) do
    with {:ok, {key, owner, kind, _value, expiry, :active}} <- entry(binding, ref) do
      :ets.insert(binding.resources, {key, owner, kind, nil, expiry, :failed})
      :ok
    end
  end

  @doc false
  @spec close(Binding.t()) :: :ok
  def close(%Binding{resources: table}) do
    :ets.delete(table)
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp entry(%Binding{} = binding, %{"id" => id, "scope" => "call", "binding_id" => binding_id, "kind" => kind})
       when binding_id == binding.id do
    case :ets.lookup(binding.resources, {:resource, id}) do
      [{_key, owner, _kind, _value, _expiry, _status}] when owner != self() ->
        Policy.error(:resource_owner_mismatch)

      [{_key, _owner, _kind, _value, _expiry, :cancelled}] ->
        Policy.error(:resource_cancelled)

      [{_key, _owner, _kind, _value, _expiry, :failed}] ->
        Policy.error(:resource_failure)

      [{_key, _owner, ^kind, _value, expiry, :active} = value] ->
        if expiry > System.monotonic_time(:millisecond) do
          {:ok, value}
        else
          {key, owner, kind, _private_value, expiry, _status} = value
          :ets.insert(binding.resources, {key, owner, kind, nil, expiry, :expired})
          Policy.error(:resource_expired)
        end

      [{_key, _owner, _kind, _value, _expiry, :expired}] ->
        Policy.error(:resource_expired)

      _ ->
        Policy.error(:invalid_resource)
    end
  rescue
    ArgumentError -> Policy.error(:resource_expired)
  end

  defp entry(_binding, _ref), do: Policy.error(:invalid_resource)
end
