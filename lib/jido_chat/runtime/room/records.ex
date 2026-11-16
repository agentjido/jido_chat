defmodule Jido.Chat.Runtime.Room.Records do
  @moduledoc false

  alias Jido.Chat.Runtime.Room.Record
  alias Jido.Chat.Runtime.Storage
  alias Jido.Chat.Runtime.Storage.Rooms

  @doc false
  @spec create(module(), map()) :: {:ok, Record.t()} | {:error, term()}
  def create(runtime, attrs) do
    with {:ok, storage} <- storage(runtime),
         {:ok, record} <- Record.new(attrs) do
      call(storage, :insert_room, [record])
    end
  end

  @doc false
  @spec get(module(), String.t()) :: {:ok, Record.t()} | {:error, term()}
  def get(runtime, id) do
    with {:ok, storage} <- storage(runtime),
         {:ok, record} <- call(storage, :get_room, [id]) do
      if is_nil(record), do: {:error, :not_found}, else: {:ok, record}
    end
  end

  @doc false
  @spec list(module(), keyword()) :: {:ok, [Record.t()]} | {:error, term()}
  def list(runtime, opts \\ []) do
    with {:ok, storage} <- storage(runtime) do
      call(storage, :list_rooms, [opts])
    end
  end

  @doc false
  @spec update(module(), String.t(), map()) :: {:ok, Record.t()} | {:error, term()}
  def update(runtime, id, attrs) do
    with {:ok, current} <- get(runtime, id) do
      update(runtime, id, current.revision, attrs)
    end
  end

  @doc false
  @spec update(module(), String.t(), pos_integer(), map()) ::
          {:ok, Record.t()} | {:error, term()}
  def update(runtime, id, expected_revision, attrs) do
    with {:ok, storage} <- storage(runtime),
         {:ok, current} <- get_from(storage, id),
         {:ok, next} <- Record.update(current, attrs),
         {:ok, record} <- call(storage, :update_room, [id, expected_revision, next]) do
      {:ok, record}
    end
  end

  @doc false
  @spec delete(module(), String.t()) :: :ok | {:error, term()}
  def delete(runtime, id) do
    with {:ok, current} <- get(runtime, id) do
      delete(runtime, id, current.revision)
    end
  end

  @doc false
  @spec delete(module(), String.t(), pos_integer()) :: :ok | {:error, term()}
  def delete(runtime, id, expected_revision) do
    with {:ok, storage} <- storage(runtime) do
      case call(storage, :delete_room, [id, expected_revision]) do
        {:ok, :ok} -> :ok
        result -> result
      end
    end
  end

  defp get_from(storage, id) do
    case call(storage, :get_room, [id]) do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  defp storage(runtime) do
    cond do
      not is_atom(runtime) or not function_exported?(runtime, :storage, 0) ->
        {:error, :invalid_runtime}

      is_nil(runtime.storage()) ->
        {:error, :room_storage_required}

      Storage.validate(runtime.storage(), [Rooms]) != :ok ->
        {:error, :unsupported_storage_capability}

      true ->
        {:ok, runtime.storage()}
    end
  end

  defp call({adapter, resource}, function, args) do
    case apply(adapter, function, [resource | args]) do
      {:error, :room_not_found} -> {:error, :not_found}
      result -> result
    end
  catch
    :exit, _reason -> {:error, :room_storage_unavailable}
  end
end
