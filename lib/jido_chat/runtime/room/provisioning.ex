defmodule Jido.Chat.Runtime.Room.Provisioning do
  @moduledoc false

  alias Jido.Chat.Runtime.Room
  alias Jido.Chat.Runtime.Room.{Declaration, Durable, Plugin, Record}
  alias Jido.Chat.Runtime.Supervisor

  @doc false
  def provision(runtime, definition_key, attrs) do
    with {:ok, definition} <- runtime.room_definition(definition_key),
         :ok <- Plugin.validate_durable_definition(definition, runtime),
         {:ok, room} <- Record.new(attrs),
         :ok <- available_runtime_id(runtime, room.id),
         {:ok, result} <- Durable.provision(runtime, definition_key, room) do
      activation = activate(runtime, room.id)
      {:ok, Map.put(result, :activation, activation)}
    end
  end

  @doc false
  def deprovision(runtime, room_id) do
    with {:ok, %Declaration{} = declaration} <- required_declaration(runtime, room_id),
         {:ok, stopped} <- stop(runtime, declaration),
         :ok <- Durable.delete_declaration(runtime, room_id, stopped.revision) do
      _ = Supervisor.reconcile(runtime)
      :ok
    end
  end

  defp available_runtime_id(runtime, room_id) do
    case Supervisor.room_status(runtime, room_id) do
      {:error, :runtime_not_started} -> :ok
      {:error, :not_managed} -> :ok
      {:ok, _entry} -> {:error, :room_declaration_conflict}
      {:error, reason} -> {:error, reason}
    end
  end

  defp activate(runtime, room_id) do
    case Supervisor.reconcile(runtime) do
      {:ok, _status} -> Supervisor.room_status(runtime, room_id)
      {:error, :runtime_not_started} -> :not_started
      {:error, {:reconcile_failed, _count, _status}} -> Supervisor.room_status(runtime, room_id)
      {:error, reason} -> {:error, reason}
    end
  end

  defp required_declaration(runtime, room_id) do
    case Durable.get_declaration(runtime, room_id) do
      {:ok, nil} -> {:error, :room_declaration_not_found}
      result -> result
    end
  end

  defp stop(runtime, declaration) do
    case Supervisor.stop_room(runtime, declaration.room_id) do
      {:ok, _entry} -> required_declaration(runtime, declaration.room_id)
      {:error, :runtime_not_started} -> stop_without_manager(runtime, declaration)
      {:error, :not_managed} -> {:error, :not_managed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp stop_without_manager(runtime, declaration) do
    with {:ok, stopped} <- Durable.set_desired(runtime, declaration.room_id, :stopped),
         {:ok, definition} <- runtime.room_definition(stopped.definition_key),
         {:ok, ref} <- runtime.room_address(stopped.room_id),
         {:ok, expected} <- Jido.Agent.instantiate(definition, id: ref.id),
         :ok <- stop_matching(runtime, ref, expected) do
      {:ok, stopped}
    end
  catch
    :exit, _reason -> {:error, :jido_unavailable}
  end

  defp stop_matching(runtime, ref, expected) do
    case Jido.resolve_agent(runtime.jido(), ref) do
      {:error, :not_found} ->
        :ok

      {:ok, server} ->
        Room.stop_matching_agent(runtime.jido(), ref, server, expected)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
