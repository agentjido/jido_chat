defmodule Jido.Chat.Runtime.Supervisor do
  @moduledoc """
  Starts one optional manager for a `Jido.Chat.Runtime` facade.

  The supervisor does not own Room or provider account Agents. The configured
  host Jido instance owns those processes.
  """

  use Supervisor

  alias Jido.Chat.Runtime.Manager

  @doc false
  @spec child_spec({module(), keyword()}) :: Supervisor.child_spec()
  def child_spec({runtime, opts}) do
    %{
      id: runtime,
      start: {__MODULE__, :start_link, [runtime, opts]},
      type: :supervisor
    }
  end

  @doc "Starts the optional managed process tree for one Runtime facade."
  @spec start_link(module(), keyword()) :: Supervisor.on_start()
  def start_link(runtime, opts \\ []) when is_atom(runtime) and is_list(opts) do
    Supervisor.start_link(__MODULE__, {runtime, opts}, name: supervisor_name(runtime))
  end

  @doc "Returns status for the managed Runtime and all declarations."
  @spec status(module()) :: {:ok, map()} | {:error, term()}
  def status(runtime), do: call(runtime, :status)

  @doc "Reconciles all managed declarations now."
  @spec reconcile(module()) :: {:ok, map()} | {:error, term()}
  def reconcile(runtime), do: call(runtime, :reconcile)

  @doc "Lists managed Room declarations."
  @spec list_rooms(module()) :: {:ok, [map()]} | {:error, term()}
  def list_rooms(runtime), do: call(runtime, {:list, :room})

  @doc "Returns status for one managed Room declaration."
  @spec room_status(module(), String.t()) :: {:ok, map()} | {:error, term()}
  def room_status(runtime, id), do: call(runtime, {:entry_status, :room, id})

  @doc "Sets one managed Room declaration to running."
  @spec start_room(module(), String.t()) :: {:ok, map()} | {:error, term()}
  def start_room(runtime, id), do: call(runtime, {:set_desired, :room, id, :running})

  @doc "Sets one managed Room declaration to stopped."
  @spec stop_room(module(), String.t()) :: {:ok, map()} | {:error, term()}
  def stop_room(runtime, id), do: call(runtime, {:set_desired, :room, id, :stopped})

  @doc "Stops and starts one managed Room declaration."
  @spec restart_room(module(), String.t()) :: {:ok, map()} | {:error, term()}
  def restart_room(runtime, id), do: call(runtime, {:restart, :room, id})

  @doc "Lists managed provider account declarations."
  @spec list_connections(module()) :: {:ok, [map()]} | {:error, term()}
  def list_connections(runtime), do: call(runtime, {:list, :connection})

  @doc "Returns status for one managed provider account declaration."
  @spec connection_status(module(), String.t()) :: {:ok, map()} | {:error, term()}
  def connection_status(runtime, id), do: call(runtime, {:entry_status, :connection, id})

  @doc "Sets one managed provider account declaration to running."
  @spec start_connection(module(), String.t()) :: {:ok, map()} | {:error, term()}
  def start_connection(runtime, id),
    do: call(runtime, {:set_desired, :connection, id, :running})

  @doc "Sets one managed provider account declaration to stopped."
  @spec stop_connection(module(), String.t()) :: {:ok, map()} | {:error, term()}
  def stop_connection(runtime, id),
    do: call(runtime, {:set_desired, :connection, id, :stopped})

  @doc "Stops and starts one managed provider account declaration."
  @spec restart_connection(module(), String.t()) :: {:ok, map()} | {:error, term()}
  def restart_connection(runtime, id), do: call(runtime, {:restart, :connection, id})

  @doc false
  @spec supervisor_name(module()) :: atom()
  def supervisor_name(runtime), do: Module.concat(runtime, ManagedSupervisor)

  @doc false
  @spec manager_name(module()) :: atom()
  def manager_name(runtime), do: Module.concat(runtime, ManagedRuntime)

  @impl true
  def init({runtime, opts}) do
    children = [
      {Manager,
       runtime: runtime,
       name: manager_name(runtime),
       rooms: Keyword.get(opts, :rooms, []),
       connections: Keyword.get(opts, :connections, []),
       reconcile_interval: Keyword.get(opts, :reconcile_interval, 5_000)}
    ]

    with :ok <- validate_runtime(runtime),
         :ok <- validate_options(opts) do
      Supervisor.init(children, strategy: :one_for_one)
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  defp call(runtime, request) do
    case Process.whereis(manager_name(runtime)) do
      nil -> {:error, :runtime_not_started}
      manager -> GenServer.call(manager, request, :infinity)
    end
  catch
    :exit, _reason -> {:error, :runtime_not_started}
  end

  defp validate_runtime(runtime) do
    if function_exported?(runtime, :jido, 0) and function_exported?(runtime, :storage, 0),
      do: :ok,
      else: {:error, :invalid_runtime}
  end

  defp validate_options(opts) do
    case Keyword.validate(opts, [:rooms, :connections, :reconcile_interval]) do
      {:ok, _opts} -> :ok
      {:error, keys} -> {:error, {:invalid_runtime_options, keys}}
    end
  end
end
