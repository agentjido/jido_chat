defmodule Jido.Chat.Runtime.Bridge.Bindings do
  @moduledoc false

  alias Jido.Chat.Runtime.Bridge.Binding
  alias Jido.Chat.Runtime.Connection.Durable, as: DurableConnection
  alias Jido.Chat.Runtime.Storage
  alias Jido.Chat.Runtime.Storage.Bindings, as: BindingStorage
  alias Jido.Chat.Runtime.Supervisor

  @page_size 1_000

  @doc false
  def create(runtime, attrs) when is_map(attrs) do
    with {:ok, binding} <- Binding.new(attrs),
         {:ok, %_{} = _declaration} <- required_connection(runtime, binding.account_id),
         {:ok, storage} <- storage(runtime),
         {:ok, binding} <- call(storage, :insert_binding, [binding]) do
      {:ok, %{binding: binding, activation: activate(runtime, binding.account_id)}}
    end
  end

  def create(_runtime, _attrs), do: {:error, :invalid_bridge_binding}

  @doc false
  def get(runtime, account_id, external_room_id) do
    with {:ok, storage} <- storage(runtime),
         do: call(storage, :get_binding, [account_id, external_room_id])
  end

  @doc false
  def list(runtime, account_id, opts \\ []) do
    with {:ok, storage} <- storage(runtime),
         do: call(storage, :list_bindings, [account_id, opts])
  end

  @doc false
  def list_all(runtime, account_id, opts \\ []) do
    with {:ok, storage} <- storage(runtime),
         do: collect(storage, account_id, opts, nil, [])
  end

  @doc false
  def update(runtime, account_id, external_room_id, expected_revision, attrs) do
    with {:ok, storage} <- storage(runtime),
         {:ok, %Binding{} = current} <- required(storage, account_id, external_room_id),
         true <- current.revision == expected_revision,
         {:ok, next} <- Binding.update(current, attrs),
         {:ok, binding} <- update_record(storage, current, next) do
      {:ok, %{binding: binding, activation: activate(runtime, account_id)}}
    else
      false -> {:error, :binding_conflict}
      {:error, _reason} = error -> error
    end
  end

  @doc false
  def disable(runtime, account_id, external_room_id) do
    with {:ok, storage} <- storage(runtime),
         {:ok, %Binding{} = current} <- required(storage, account_id, external_room_id),
         {:ok, next} <- Binding.set_enabled(current, false),
         {:ok, binding} <- update_record(storage, current, next) do
      {:ok, %{binding: binding, activation: activate(runtime, account_id)}}
    end
  end

  defp required_connection(runtime, account_id) do
    case DurableConnection.get(runtime, account_id) do
      {:ok, nil} -> {:error, :connection_not_found}
      result -> result
    end
  end

  defp required(storage, account_id, external_room_id) do
    case call(storage, :get_binding, [account_id, external_room_id]) do
      {:ok, nil} -> {:error, :binding_not_found}
      result -> result
    end
  end

  defp update_record(_storage, current, current), do: {:ok, current}

  defp update_record(storage, current, next),
    do:
      call(storage, :update_binding, [
        current.account_id,
        current.external_room_id,
        current.revision,
        next
      ])

  defp collect(storage, account_id, opts, after_id, pages) do
    page_opts =
      opts
      |> Keyword.delete(:after)
      |> Keyword.put(:limit, @page_size)
      |> then(fn options -> if after_id, do: Keyword.put(options, :after, after_id), else: options end)

    with {:ok, page} <- call(storage, :list_bindings, [account_id, page_opts]) do
      case List.last(page) do
        nil ->
          {:ok, flatten_pages(pages)}

        _last when length(page) < @page_size ->
          {:ok, flatten_pages([page | pages])}

        %{external_room_id: ^after_id} ->
          {:error, :invalid_binding_page}

        last ->
          collect(storage, account_id, opts, last.external_room_id, [page | pages])
      end
    end
  end

  defp flatten_pages(pages), do: pages |> Enum.reverse() |> List.flatten()

  defp activate(runtime, account_id) do
    case Supervisor.reconcile(runtime) do
      {:ok, _status} -> Supervisor.connection_status(runtime, account_id)
      {:error, :runtime_not_started} -> :not_started
      {:error, {:reconcile_failed, _count, _status}} -> Supervisor.connection_status(runtime, account_id)
      {:error, reason} -> {:error, reason}
    end
  end

  defp storage(runtime) do
    cond do
      not is_atom(runtime) or not function_exported?(runtime, :storage, 0) ->
        {:error, :invalid_runtime}

      is_nil(runtime.storage()) ->
        {:error, :bridge_storage_required}

      Storage.validate(runtime.storage(), [BindingStorage]) != :ok ->
        {:error, :unsupported_storage_capability}

      true ->
        {:ok, runtime.storage()}
    end
  end

  defp call({adapter, resource}, function, args) do
    apply(adapter, function, [resource | args])
  catch
    :exit, _reason -> {:error, :bridge_storage_unavailable}
  end
end
