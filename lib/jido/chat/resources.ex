defmodule Jido.Chat.Resources do
  @moduledoc false

  alias Jido.Chat.Binding
  alias Jido.Chat.Signal.Policy
  @kinds ~w(file media stream card modal result)
  @type owner :: Binding.t() | %{required(:id) => String.t(), required(:resources) => :ets.table()}

  @doc false
  @spec put(owner(), String.t(), term(), keyword()) :: {:ok, map()} | {:error, Jido.Chat.Errors.Contract.t()}
  def put(%{id: id, resources: _table} = binding, kind, value, opts) when is_binary(id) and is_list(opts) do
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
  @spec resolve(owner(), map()) :: {:ok, term()} | {:error, Jido.Chat.Errors.Contract.t()}
  def resolve(binding, ref) do
    with {:ok, {_key, _owner, _kind, value, _expiry, :active}} <- entry(binding, ref) do
      {:ok, value}
    end
  end

  @doc false
  @spec cancel(owner(), map()) :: :ok | {:error, Jido.Chat.Errors.Contract.t()}
  def cancel(binding, ref) do
    with {:ok, {key, owner, kind, _value, expiry, :active}} <- entry(binding, ref) do
      :ets.insert(binding.resources, {key, owner, kind, nil, expiry, :cancelled})
      :ok
    end
  end

  @doc false
  @spec fail(owner(), map()) :: :ok | {:error, Jido.Chat.Errors.Contract.t()}
  def fail(binding, ref) do
    with {:ok, {key, owner, kind, _value, expiry, :active}} <- entry(binding, ref) do
      :ets.insert(binding.resources, {key, owner, kind, nil, expiry, :failed})
      :ok
    end
  end

  @doc false
  @spec close(owner()) :: :ok
  def close(%{resources: table}) do
    :ets.delete(table)
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp entry(%{id: owner_id, resources: _table} = binding, %{
         "id" => id,
         "scope" => "call",
         "binding_id" => binding_id,
         "kind" => kind
       })
       when binding_id == owner_id do
    case :ets.lookup(binding.resources, {:resource, id}) do
      [{_key, _owner, ^kind, _value, _expiry, _status} = value] ->
        validate_entry(binding, value)

      _ ->
        Policy.error(:invalid_resource)
    end
  rescue
    ArgumentError -> Policy.error(:resource_expired)
  end

  defp entry(_binding, _ref), do: Policy.error(:invalid_resource)

  defp validate_entry(binding, {key, owner, kind, _value, expiry, status} = entry) do
    cond do
      status == :active and (expiry <= System.monotonic_time(:millisecond) or not Process.alive?(owner)) ->
        :ets.insert(binding.resources, {key, owner, kind, nil, expiry, :expired})
        Policy.error(:resource_expired)

      owner != self() ->
        Policy.error(:resource_owner_mismatch)

      status == :cancelled ->
        Policy.error(:resource_cancelled)

      status == :failed ->
        Policy.error(:resource_failure)

      status == :expired ->
        Policy.error(:resource_expired)

      status == :active ->
        {:ok, entry}

      true ->
        Policy.error(:invalid_resource)
    end
  end
end
