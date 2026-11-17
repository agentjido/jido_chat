defmodule Jido.Chat.Runtime.Connection.Durable do
  @moduledoc false

  alias Jido.Chat.Runtime.Connection.Declaration
  alias Jido.Chat.Runtime.Storage
  alias Jido.Chat.Runtime.Storage.Connections

  @doc false
  def create(runtime, definition_key, attrs) when is_map(attrs) do
    with {:ok, _definition} <- runtime.connection_definition(definition_key),
         {:ok, storage} <- storage(runtime),
         attrs <- Map.put(attrs, :definition_key, definition_key),
         {:ok, declaration} <- Declaration.new(attrs),
         do: call(storage, :insert_connection, [declaration])
  end

  def create(_runtime, _definition_key, _attrs), do: {:error, :invalid_connection_declaration}

  @doc false
  def get(runtime, account_id) do
    with {:ok, storage} <- storage(runtime),
         do: call(storage, :get_connection, [account_id])
  end

  @doc false
  def list(runtime) do
    with {:ok, storage} <- storage(runtime),
         do: call(storage, :list_connections, [])
  end

  @doc false
  def update(runtime, account_id, expected_revision, attrs) do
    with {:ok, storage} <- storage(runtime),
         {:ok, %Declaration{} = current} <- required(storage, account_id),
         true <- current.revision == expected_revision,
         {:ok, next} <- Declaration.update(current, attrs) do
      update_record(storage, current, next)
    else
      false -> {:error, :connection_conflict}
      {:error, _reason} = error -> error
    end
  end

  @doc false
  def set_desired(runtime, account_id, desired) do
    with {:ok, storage} <- storage(runtime),
         {:ok, %Declaration{} = current} <- required(storage, account_id),
         {:ok, next} <- Declaration.set_desired(current, desired),
         do: update_record(storage, current, next)
  end

  defp required(storage, account_id) do
    case call(storage, :get_connection, [account_id]) do
      {:ok, nil} -> {:error, :connection_not_found}
      result -> result
    end
  end

  defp update_record(_storage, current, current), do: {:ok, current}

  defp update_record(storage, current, next),
    do: call(storage, :update_connection, [current.account_id, current.revision, next])

  defp storage(runtime) do
    cond do
      not is_atom(runtime) or not function_exported?(runtime, :storage, 0) ->
        {:error, :invalid_runtime}

      is_nil(runtime.storage()) ->
        {:error, :connection_storage_required}

      Storage.validate(runtime.storage(), [Connections]) != :ok ->
        {:error, :unsupported_storage_capability}

      true ->
        {:ok, runtime.storage()}
    end
  end

  defp call({adapter, resource}, function, args) do
    apply(adapter, function, [resource | args])
  catch
    :exit, _reason -> {:error, :connection_storage_unavailable}
  end
end
