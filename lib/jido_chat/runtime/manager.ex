defmodule Jido.Chat.Runtime.Manager do
  @moduledoc false

  use GenServer

  alias Jido.AgentServer.Snapshot
  alias Jido.Chat.Runtime.Bridge.Bindings
  alias Jido.Chat.Runtime.{Connection, Room}
  alias Jido.Chat.Runtime.Connection.Declaration, as: ConnectionDeclaration
  alias Jido.Chat.Runtime.Connection.Durable, as: DurableConnection
  alias Jido.Chat.Runtime.Room.Declaration, as: RoomDeclaration
  alias Jido.Chat.Runtime.Room.Durable, as: DurableRoom

  @max_id_bytes 256
  @entry_kinds [:room, :connection]

  @type entry :: %{
          id: String.t(),
          definition: module() | Jido.Agent.t(),
          desired: :running | :stopped,
          state: :pending | :running | :stopped | :error,
          ref: Jido.Agent.Address.t() | nil,
          pid: pid() | nil,
          error: term() | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    runtime = Keyword.fetch!(opts, :runtime)

    with {:ok, startup_rooms} <- declarations(Keyword.get(opts, :rooms, []), :room),
         {:ok, durable_rooms} <- durable_declarations(runtime),
         {:ok, rooms} <- merge_rooms(startup_rooms, durable_rooms),
         {:ok, startup_connections} <- declarations(Keyword.get(opts, :connections, []), :connection),
         {:ok, durable_connections} <- durable_connections(runtime),
         {:ok, connections} <- merge_connections(startup_connections, durable_connections),
         {:ok, interval} <- reconcile_interval(Keyword.get(opts, :reconcile_interval, 5_000)) do
      state = %{
        runtime: runtime,
        rooms: rooms,
        connections: connections,
        reconcile_interval: interval,
        reconcile_timer: nil,
        declaration_errors: %{room: nil, connection: nil},
        ready: false
      }

      {:ok, state, {:continue, :initial_reconcile}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:initial_reconcile, state) do
    state = state |> reconcile_all() |> Map.put(:ready, true) |> schedule_reconcile()
    {:noreply, state}
  end

  @impl true
  def handle_call(:status, _from, state), do: {:reply, {:ok, status(state)}, state}

  def handle_call(:reconcile, _from, state) do
    state = state |> cancel_reconcile() |> reconcile_all() |> schedule_reconcile()
    {:reply, reconcile_result(state), state}
  end

  def handle_call({:list, kind}, _from, state) when kind in @entry_kinds do
    {:reply, {:ok, group(state, kind) |> entry_views()}, state}
  end

  def handle_call({:entry_status, kind, id}, _from, state) when kind in @entry_kinds do
    reply =
      case Map.fetch(group(state, kind), id) do
        {:ok, entry} -> {:ok, entry_view(entry)}
        :error -> {:error, :not_managed}
      end

    {:reply, reply, state}
  end

  def handle_call({:set_desired, kind, id, desired}, _from, state)
      when kind in @entry_kinds and desired in [:running, :stopped] do
    case set_desired(state, kind, id, desired) do
      {:ok, state} ->
        state = reconcile_one(state, kind, id)
        {:reply, lifecycle_result(state, kind, id, desired), state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:restart, kind, id}, _from, state) when kind in @entry_kinds do
    case set_desired(state, kind, id, :stopped) do
      {:ok, state} ->
        state = reconcile_one(state, kind, id)

        case lifecycle_result(state, kind, id, :stopped) do
          {:ok, _entry} ->
            {:ok, state} = set_desired(state, kind, id, :running)
            state = reconcile_one(state, kind, id)
            {:reply, lifecycle_result(state, kind, id, :running), state}

          {:error, _reason} = error ->
            {:reply, error, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({:reconcile, token}, %{reconcile_timer: {_timer, token}} = state) do
    state = state |> Map.put(:reconcile_timer, nil) |> reconcile_all() |> schedule_reconcile()
    {:noreply, state}
  end

  def handle_info({:reconcile, _stale_token}, state), do: {:noreply, state}

  @impl true
  def terminate(reason, state) when reason in [:normal, :shutdown] do
    stop_managed_agents(state)
    :ok
  end

  def terminate({:shutdown, _reason}, state) do
    stop_managed_agents(state)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp declarations(values, kind) when is_map(values),
    do: declarations(Map.to_list(values), kind)

  defp declarations(values, kind) when is_list(values) do
    Enum.reduce_while(values, {:ok, %{}}, fn
      {id, definition}, {:ok, declarations} ->
        cond do
          not valid_id?(id) ->
            {:halt, {:error, {:invalid_declaration_id, kind, id}}}

          Map.has_key?(declarations, id) ->
            {:halt, {:error, {:duplicate_declaration, kind, id}}}

          true ->
            {:cont, {:ok, Map.put(declarations, id, new_entry(id, definition, :startup))}}
        end

      value, _acc ->
        {:halt, {:error, {:invalid_declaration, kind, value}}}
    end)
  end

  defp declarations(value, kind), do: {:error, {:invalid_declarations, kind, value}}

  defp new_entry(id, definition, source) do
    %{
      id: id,
      definition: definition,
      definition_key: nil,
      declaration: nil,
      bindings: nil,
      source: source,
      revision: nil,
      resolution_error: nil,
      desired: :running,
      state: :pending,
      ref: nil,
      pid: nil,
      error: nil
    }
  end

  defp valid_id?(value),
    do: is_binary(value) and byte_size(value) in 1..@max_id_bytes

  defp reconcile_interval(:infinity), do: {:ok, :infinity}
  defp reconcile_interval(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp reconcile_interval(value), do: {:error, {:invalid_reconcile_interval, value}}

  defp reconcile_all(state) do
    state
    |> refresh_durable_rooms()
    |> refresh_durable_connections()
    |> reconcile_group(:room)
    |> reconcile_group(:connection)
  end

  defp reconcile_group(state, kind) do
    group(state, kind)
    |> Map.keys()
    |> Enum.sort()
    |> Enum.reduce(state, &reconcile_one(&2, kind, &1))
  end

  defp reconcile_one(state, kind, id) do
    entry = Map.fetch!(group(state, kind), id)
    entry = safe_reconcile(entry, kind, state.runtime)
    put_entry(state, kind, entry)
  end

  defp safe_reconcile(entry, kind, runtime) do
    if entry.resolution_error,
      do: mark_error(entry, entry.resolution_error),
      else: reconcile_entry(entry, kind, runtime)
  rescue
    error -> mark_error(entry, {:exception, error.__struct__})
  catch
    :exit, _reason -> mark_error(entry, :jido_unavailable)
    kind, _reason -> mark_error(entry, {:runtime_failure, kind})
  end

  defp reconcile_entry(%{desired: :running} = entry, :room, runtime),
    do: ensure_room_running(entry, runtime)

  defp reconcile_entry(%{desired: :running} = entry, :connection, runtime),
    do: ensure_connection_running(entry, runtime)

  defp reconcile_entry(%{desired: :stopped} = entry, kind, runtime),
    do: ensure_stopped(entry, kind, runtime)

  defp ensure_room_running(entry, runtime) do
    with {:ok, ref} <- Jido.agent_address(runtime.jido(), entry.id),
         {:ok, expected} <- Jido.Agent.instantiate(entry.definition, id: ref.id),
         :ok <- require_plugin(expected, Jido.Chat.Runtime.Room.Plugin, :one_room_plugin_required) do
      case Jido.resolve_agent(runtime.jido(), ref) do
        {:ok, server} -> adopt(entry, ref, server, expected)
        {:error, :not_found} -> start_room(entry, runtime, ref)
        {:error, reason} -> mark_error(entry, reason, ref)
      end
    else
      {:error, reason} -> mark_error(entry, reason)
    end
  end

  defp start_room(entry, runtime, ref) do
    with {:ok, initial_state} <- Room.Plugin.hydrate_state(entry.definition, runtime, ref.id),
         {:ok, expected} <- Jido.Agent.instantiate(entry.definition, id: ref.id, state: initial_state),
         :ok <- require_plugin(expected, Jido.Chat.Runtime.Room.Plugin, :one_room_plugin_required) do
      case Room.start_agent(runtime.jido(), ref, expected) do
        {:ok, server} -> adopt(entry, ref, server, expected)
        {:error, {:already_started, server}} -> adopt(entry, ref, server, expected)
        {:error, reason} -> mark_error(entry, reason, ref)
      end
    else
      {:error, reason} -> mark_error(entry, reason, ref)
    end
  end

  defp ensure_connection_running(entry, runtime) do
    with {:ok, ref, expected} <-
           Connection.expected(
             runtime,
             entry.id,
             entry.definition,
             entry.declaration,
             entry.bindings
           ) do
      case Jido.resolve_agent(runtime.jido(), ref) do
        {:ok, server} -> reconcile_live_connection(entry, runtime, ref, server, expected)
        {:error, :not_found} -> start_connection(entry, runtime)
        {:error, reason} -> mark_error(entry, reason, ref)
      end
    else
      {:error, reason} -> mark_error(entry, reason)
    end
  end

  defp start_connection(entry, runtime) do
    opts = [declaration: entry.declaration, bindings: entry.bindings]

    with {:ok, ref, expected} <- Connection.prepare(runtime, entry.id, entry.definition, opts) do
      case Connection.start_prepared(runtime, entry.id, ref, expected) do
        {:ok, ^ref, server} ->
          mark_running(entry, ref, server)

        {:error, {:already_started, server}} ->
          reconcile_live_connection(entry, runtime, ref, server, expected)

        {:error, reason} ->
          mark_error(entry, reason, ref)
      end
    else
      {:error, reason} -> mark_error(entry, reason)
    end
  end

  defp reconcile_live_connection(entry, runtime, ref, server, expected) do
    with :ok <- Jido.AgentServer.await_ready(server),
         %Snapshot{agent: actual, agent_address: ^ref} <- Jido.AgentServer.snapshot(server) do
      cond do
        Connection.same_configuration?(expected, actual) ->
          mark_running(entry, ref, server)

        Room.same_definition?(expected, actual) ->
          replace_connection(entry, runtime, ref, server, expected)

        true ->
          mark_error(entry, :address_in_use, ref)
      end
    else
      %Snapshot{} -> mark_error(entry, :address_mismatch, ref)
      {:error, reason} -> mark_error(entry, reason, ref)
    end
  end

  defp replace_connection(entry, runtime, ref, server, expected) do
    case Room.stop_matching_agent(runtime.jido(), ref, server, expected) do
      :ok -> start_connection(entry, runtime)
      {:error, reason} -> mark_error(entry, reason, ref)
    end
  end

  defp adopt(entry, ref, server, expected) do
    with :ok <- Jido.AgentServer.await_ready(server),
         %Snapshot{agent: actual, agent_address: ^ref} <- Jido.AgentServer.snapshot(server),
         true <- Room.same_definition?(expected, actual) do
      mark_running(entry, ref, server)
    else
      false -> mark_error(entry, :address_in_use, ref)
      %Snapshot{} -> mark_error(entry, :address_mismatch, ref)
      {:error, reason} -> mark_error(entry, reason, ref)
    end
  end

  defp ensure_stopped(entry, kind, runtime) do
    with {:ok, ref} <- entry_ref(entry, kind, runtime),
         {:ok, expected} <- expected_agent(entry, kind, runtime, ref) do
      case Jido.resolve_agent(runtime.jido(), ref) do
        {:error, :not_found} -> mark_stopped(entry, ref)
        {:ok, server} -> stop_matching(entry, runtime, ref, server, expected)
        {:error, reason} -> mark_error(entry, reason, ref)
      end
    else
      {:error, reason} -> mark_error(entry, reason)
    end
  end

  defp expected_agent(entry, :room, _runtime, ref),
    do: Jido.Agent.instantiate(entry.definition, id: ref.id)

  defp expected_agent(entry, :connection, _runtime, ref),
    do: Jido.Agent.instantiate(entry.definition, id: ref.id)

  defp stop_matching(entry, runtime, ref, server, expected) do
    case Room.stop_matching_agent(runtime.jido(), ref, server, expected) do
      :ok -> mark_stopped(entry, ref)
      {:error, reason} -> mark_error(entry, reason, ref)
    end
  end

  defp entry_ref(entry, :room, runtime),
    do: Jido.agent_address(runtime.jido(), entry.id)

  defp entry_ref(entry, :connection, runtime),
    do: Connection.ref(runtime, entry.id)

  defp require_plugin(agent, provider, error) do
    if Enum.count(agent.plugins, &(&1.provider == provider)) == 1,
      do: :ok,
      else: {:error, error}
  end

  defp mark_running(entry, ref, server),
    do: %{entry | state: :running, ref: ref, pid: server, error: nil}

  defp mark_stopped(entry, ref),
    do: %{entry | state: :stopped, ref: ref, pid: nil, error: nil}

  defp mark_error(entry, reason, ref \\ nil),
    do: %{entry | state: :error, ref: ref || entry.ref, pid: nil, error: public_error(reason)}

  defp public_error(reason) when is_atom(reason), do: reason

  defp public_error({tag, value}) when is_atom(tag) and is_atom(value),
    do: {tag, value}

  defp public_error({tag, value}) when is_atom(tag) and is_integer(value),
    do: {tag, value}

  defp public_error({tag, kind, id}) when is_atom(tag) and is_atom(kind) and is_binary(id),
    do: {tag, kind, id}

  defp public_error(%{__struct__: module}) when is_atom(module),
    do: {:runtime_error, module}

  defp public_error(_reason), do: :runtime_error

  defp group(state, :room), do: state.rooms
  defp group(state, :connection), do: state.connections

  defp put_entry(state, :room, entry), do: put_in(state.rooms[entry.id], entry)
  defp put_entry(state, :connection, entry), do: put_in(state.connections[entry.id], entry)

  defp update_entry(state, kind, id, update) do
    case Map.fetch(group(state, kind), id) do
      {:ok, entry} -> {:ok, put_entry(state, kind, update.(entry))}
      :error -> {:error, :not_managed}
    end
  end

  defp set_desired(state, :room, id, desired) do
    case Map.fetch(state.rooms, id) do
      {:ok, %{source: :durable} = entry} ->
        with {:ok, declaration} <- DurableRoom.set_desired(state.runtime, id, desired) do
          {:ok,
           put_entry(state, :room, %{
             entry
             | desired: declaration.desired,
               revision: declaration.revision
           })}
        end

      {:ok, _entry} ->
        update_entry(state, :room, id, &Map.put(&1, :desired, desired))

      :error ->
        {:error, :not_managed}
    end
  end

  defp set_desired(state, :connection, id, desired) do
    case Map.fetch(state.connections, id) do
      {:ok, %{source: :durable} = entry} ->
        with {:ok, declaration} <- DurableConnection.set_desired(state.runtime, id, desired) do
          {:ok,
           put_entry(state, :connection, %{
             entry
             | declaration: declaration,
               desired: declaration.desired,
               revision: declaration.revision
           })}
        end

      {:ok, _entry} ->
        update_entry(state, :connection, id, &Map.put(&1, :desired, desired))

      :error ->
        {:error, :not_managed}
    end
  end

  defp lifecycle_result(state, kind, id, desired) do
    entry = Map.fetch!(group(state, kind), id)
    target = if desired == :running, do: :running, else: :stopped
    view = entry_view(entry)

    if entry.state == target,
      do: {:ok, view},
      else: {:error, {:lifecycle_failed, view}}
  end

  defp status(state) do
    rooms = entry_views(state.rooms)
    connections = entry_views(state.connections)
    declaration_errors = Map.reject(state.declaration_errors, fn {_kind, error} -> is_nil(error) end)

    errors =
      Enum.count(rooms ++ connections, &(&1.state == :error)) +
        map_size(declaration_errors)

    %{
      ready: state.ready,
      healthy: state.ready and errors == 0,
      error_count: errors,
      declaration_error: state.declaration_errors.room || state.declaration_errors.connection,
      declaration_errors: declaration_errors,
      rooms: rooms,
      connections: connections
    }
  end

  defp entry_views(entries) do
    entries
    |> Map.values()
    |> Enum.sort_by(& &1.id)
    |> Enum.map(&entry_view/1)
  end

  defp entry_view(entry) do
    %{
      id: entry.id,
      definition: definition_name(entry.definition),
      definition_key: entry.definition_key,
      source: entry.source,
      revision: entry.revision,
      desired: entry.desired,
      state: entry.state,
      ref: entry.ref,
      pid: entry.pid,
      error: entry.error
    }
  end

  defp definition_name(definition) when is_atom(definition), do: definition
  defp definition_name(%Jido.Agent{module: module}) when module not in [nil, true, false], do: module
  defp definition_name(%Jido.Agent{name: name}), do: name
  defp definition_name(_definition), do: :invalid_definition

  defp reconcile_result(state) do
    status = status(state)

    if status.healthy,
      do: {:ok, status},
      else: {:error, {:reconcile_failed, status.error_count, status}}
  end

  defp schedule_reconcile(%{reconcile_interval: :infinity} = state), do: state

  defp schedule_reconcile(state) do
    token = make_ref()
    timer = Process.send_after(self(), {:reconcile, token}, state.reconcile_interval)
    %{state | reconcile_timer: {timer, token}}
  end

  defp cancel_reconcile(%{reconcile_timer: nil} = state), do: state

  defp cancel_reconcile(state) do
    {timer, _token} = state.reconcile_timer
    _ = Process.cancel_timer(timer)
    %{state | reconcile_timer: nil}
  end

  defp stop_managed_agents(state) do
    for kind <- @entry_kinds,
        entry <- Map.values(group(state, kind)) do
      _ = safe_reconcile(%{entry | desired: :stopped}, kind, state.runtime)
    end

    :ok
  end

  defp durable_declarations(runtime) do
    if is_nil(runtime.storage()) do
      {:ok, %{}}
    else
      case DurableRoom.list_declarations(runtime) do
        {:ok, declarations} ->
          declarations
          |> Enum.reduce_while({:ok, %{}}, fn declaration, {:ok, entries} ->
            case durable_entry(runtime, declaration) do
              {:ok, entry} -> {:cont, {:ok, Map.put(entries, entry.id, entry)}}
              {:error, reason} -> {:halt, {:error, reason}}
            end
          end)

        {:error, :unsupported_storage_capability} ->
          {:ok, %{}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp durable_entry(runtime, %RoomDeclaration{} = declaration) do
    {definition, error} =
      case runtime.room_definition(declaration.definition_key) do
        {:ok, definition} -> {definition, nil}
        {:error, reason} -> {nil, reason}
      end

    {:ok,
     %{
       id: declaration.room_id,
       definition: definition,
       definition_key: declaration.definition_key,
       source: :durable,
       revision: declaration.revision,
       resolution_error: error,
       desired: declaration.desired,
       state: :pending,
       ref: nil,
       pid: nil,
       error: nil
     }}
  end

  defp durable_entry(_runtime, _declaration), do: {:error, :invalid_room_declaration}

  defp merge_rooms(startup, durable), do: merge_declarations(startup, durable, :room)

  defp refresh_durable_rooms(state),
    do: refresh_durable(state, :room, &durable_declarations/1)

  defp durable_connections(runtime) do
    if is_nil(runtime.storage()) or map_size(runtime.connection_definitions()) == 0 do
      {:ok, %{}}
    else
      case DurableConnection.list(runtime) do
        {:ok, declarations} ->
          Enum.reduce_while(declarations, {:ok, %{}}, fn declaration, {:ok, entries} ->
            case durable_connection_entry(runtime, declaration) do
              {:ok, entry} -> {:cont, {:ok, Map.put(entries, entry.id, entry)}}
              {:error, reason} -> {:halt, {:error, reason}}
            end
          end)

        {:error, :unsupported_storage_capability} ->
          {:ok, %{}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp durable_connection_entry(runtime, %ConnectionDeclaration{} = declaration) do
    {definition, definition_error} =
      case runtime.connection_definition(declaration.definition_key) do
        {:ok, definition} -> {definition, nil}
        {:error, reason} -> {nil, reason}
      end

    {bindings, binding_error} =
      case Bindings.list_all(runtime, declaration.account_id, enabled: true) do
        {:ok, bindings} -> {bindings, nil}
        {:error, :unsupported_storage_capability} -> {[], nil}
        {:error, reason} -> {[], reason}
      end

    {:ok,
     %{
       id: declaration.account_id,
       definition: definition,
       definition_key: declaration.definition_key,
       declaration: declaration,
       bindings: bindings,
       source: :durable,
       revision: declaration.revision,
       resolution_error: definition_error || binding_error,
       desired: declaration.desired,
       state: :pending,
       ref: nil,
       pid: nil,
       error: nil
     }}
  end

  defp durable_connection_entry(_runtime, _declaration),
    do: {:error, :invalid_connection_declaration}

  defp merge_connections(startup, durable),
    do: merge_declarations(startup, durable, :connection)

  defp refresh_durable_connections(state),
    do: refresh_durable(state, :connection, &durable_connections/1)

  defp refresh_durable(state, kind, load) do
    case load.(state.runtime) do
      {:ok, durable} ->
        current = group(state, kind)
        startup = Map.reject(current, fn {_id, entry} -> entry.source == :durable end)
        removed = removed_entries(current, durable, kind, state.runtime)
        durable = preserve_runtime_state(durable, current)

        case merge_declarations(startup, Map.merge(durable, removed), kind) do
          {:ok, entries} ->
            state
            |> put_group(kind, entries)
            |> put_declaration_error(kind, nil)

          {:error, reason} ->
            put_declaration_error(state, kind, public_error(reason))
        end

      {:error, reason} ->
        put_declaration_error(state, kind, public_error(reason))
    end
  end

  defp removed_entries(current, durable, kind, runtime) do
    current
    |> Map.filter(fn {id, entry} -> entry.source == :durable and not Map.has_key?(durable, id) end)
    |> Map.new(fn {id, entry} ->
      {id, safe_reconcile(%{entry | desired: :stopped}, kind, runtime)}
    end)
    |> Map.reject(fn {_id, entry} -> entry.state == :stopped end)
  end

  defp preserve_runtime_state(durable, current) do
    Map.new(durable, fn {id, entry} ->
      case Map.get(current, id) do
        %{source: :durable} = previous ->
          {id, %{entry | state: previous.state, ref: previous.ref, pid: previous.pid, error: previous.error}}

        _other ->
          {id, entry}
      end
    end)
  end

  defp merge_declarations(startup, durable, kind) do
    case Map.keys(startup) |> Enum.find(&Map.has_key?(durable, &1)) do
      nil -> {:ok, Map.merge(startup, durable)}
      id -> {:error, {:duplicate_declaration, kind, id}}
    end
  end

  defp put_group(state, :room, entries), do: %{state | rooms: entries}
  defp put_group(state, :connection, entries), do: %{state | connections: entries}

  defp put_declaration_error(state, kind, error) do
    %{state | declaration_errors: Map.put(state.declaration_errors, kind, error)}
  end
end
