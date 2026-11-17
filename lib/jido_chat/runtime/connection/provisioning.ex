defmodule Jido.Chat.Runtime.Connection.Provisioning do
  @moduledoc false

  alias Jido.Chat.Runtime.Connection
  alias Jido.Chat.Runtime.Connection.{Declaration, Durable}
  alias Jido.Chat.Runtime.Room
  alias Jido.Chat.Runtime.Supervisor

  @doc false
  def provision(runtime, definition_key, attrs) when is_map(attrs) do
    with {:ok, definition} <- runtime.connection_definition(definition_key),
         :ok <- Connection.validate_definition(definition),
         account_id when is_binary(account_id) <- Map.get(attrs, :account_id, Map.get(attrs, "account_id")),
         :ok <- available_runtime_id(runtime, account_id),
         {:ok, declaration} <- Durable.create(runtime, definition_key, attrs) do
      {:ok, %{declaration: declaration, activation: activate(runtime, account_id)}}
    else
      nil -> {:error, :invalid_connection_declaration}
      {:error, _reason} = error -> error
      _other -> {:error, :invalid_connection_declaration}
    end
  end

  def provision(_runtime, _definition_key, _attrs), do: {:error, :invalid_connection_declaration}

  @doc false
  def update(runtime, account_id, expected_revision, attrs) do
    with {:ok, declaration} <- Durable.update(runtime, account_id, expected_revision, attrs) do
      {:ok, %{declaration: declaration, activation: activate(runtime, account_id)}}
    end
  end

  @doc false
  def deprovision(runtime, account_id) do
    with {:ok, %Declaration{}} <- required(runtime, account_id),
         {:ok, stopped} <- Durable.set_desired(runtime, account_id, :stopped),
         :ok <- stop(runtime, stopped) do
      :ok
    end
  end

  defp available_runtime_id(runtime, account_id) do
    case Supervisor.connection_status(runtime, account_id) do
      {:error, :runtime_not_started} -> :ok
      {:error, :not_managed} -> :ok
      {:ok, _entry} -> {:error, :connection_conflict}
      {:error, reason} -> {:error, reason}
    end
  end

  defp activate(runtime, account_id) do
    case Supervisor.reconcile(runtime) do
      {:ok, _status} -> Supervisor.connection_status(runtime, account_id)
      {:error, :runtime_not_started} -> :not_started
      {:error, {:reconcile_failed, _count, _status}} -> Supervisor.connection_status(runtime, account_id)
      {:error, reason} -> {:error, reason}
    end
  end

  defp required(runtime, account_id) do
    case Durable.get(runtime, account_id) do
      {:ok, nil} -> {:error, :connection_not_found}
      result -> result
    end
  end

  defp stop(runtime, stopped) do
    case Supervisor.stop_connection(runtime, stopped.account_id) do
      {:ok, _entry} -> :ok
      {:error, :runtime_not_started} -> stop_without_manager(runtime, stopped)
      {:error, :not_managed} -> stop_without_manager(runtime, stopped)
      {:error, reason} -> {:error, reason}
    end
  end

  defp stop_without_manager(runtime, declaration) do
    with {:ok, definition} <- runtime.connection_definition(declaration.definition_key),
         {:ok, ref} <- Connection.ref(runtime, declaration.account_id),
         {:ok, expected} <- Jido.Agent.instantiate(definition, id: ref.id) do
      case Jido.resolve_agent(runtime.jido(), ref) do
        {:error, :not_found} -> :ok
        {:ok, server} -> Room.stop_matching_agent(runtime.jido(), ref, server, expected)
        {:error, reason} -> {:error, reason}
      end
    end
  catch
    :exit, _reason -> {:error, :jido_unavailable}
  end
end
