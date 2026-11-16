defmodule Jido.Chat.Runtime.Storage.Dets do
  @moduledoc """
  Host-owned, local durable Runtime storage backed by Erlang DETS.

  This adapter implements every Runtime storage capability and retains one
  versioned snapshot. It is intended for local and single-node use. A host that
  needs indexed queries, multi-node coordination, or database migrations can
  implement the same capability behaviours with Ecto, Ash, or another store.

  The DETS file is trusted application data. Do not open a file supplied by an
  untrusted caller.
  """

  use GenServer

  alias Jido.Chat.Runtime.Storage
  alias Jido.Chat.Runtime.Storage.{Commit, Engine, Links, Outbox, Rooms}

  use Storage.Adapter,
    capabilities: [Links, Outbox, Rooms, Commit]

  @format_version 2
  @readable_versions [1, @format_version]
  @snapshot_key :jido_chat_runtime_snapshot

  @type option ::
          {:path, Path.t()}
          | {:table, atom()}
          | {:name, GenServer.name()}
          | {:id, term()}

  @doc "Starts a durable storage resource for one explicit DETS table and path."
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    name = Keyword.get(opts, :name)
    server_opts = if is_nil(name), do: [], else: [name: name]
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc false
  @spec child_spec([option()]) :: Supervisor.child_spec()
  def child_spec(opts) do
    table = Keyword.fetch!(opts, :table)

    %{
      id: Keyword.get(opts, :id, {__MODULE__, table}),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @doc "Returns the stored snapshot format version."
  @spec format_version() :: pos_integer()
  def format_version, do: @format_version

  @impl Links
  def put_link(server, link), do: GenServer.call(server, {:command, {:put_link, link}})

  @impl Links
  def link_for_local(server, account_id, local_message_id),
    do: GenServer.call(server, {:query, {:link_for_local, account_id, local_message_id}})

  @impl Links
  def link_for_external(server, account_id, external_room_id, external_message_id),
    do: GenServer.call(server, {:query, {:link_for_external, account_id, external_room_id, external_message_id}})

  @impl Outbox
  def put_work(server, work), do: GenServer.call(server, {:command, {:put_work, work}})

  @impl Outbox
  def get_work(server, id), do: GenServer.call(server, {:query, {:get_work, id}})

  @impl Outbox
  def list_work(server, account_id, opts \\ []),
    do: GenServer.call(server, {:query, {:list_work, account_id, opts}})

  @impl Outbox
  def update_work(server, id, expected_status, changes),
    do: GenServer.call(server, {:command, {:update_work, id, expected_status, changes}})

  @impl Rooms
  def insert_room(server, record),
    do: GenServer.call(server, {:command, {:insert_room, record}})

  @impl Rooms
  def get_room(server, id), do: GenServer.call(server, {:query, {:get_room, id}})

  @impl Rooms
  def list_rooms(server, opts \\ []),
    do: GenServer.call(server, {:query, {:list_rooms, opts}})

  @impl Rooms
  def update_room(server, id, expected_revision, record),
    do: GenServer.call(server, {:command, {:update_room, id, expected_revision, record}})

  @impl Rooms
  def delete_room(server, id, expected_revision),
    do: GenServer.call(server, {:command, {:delete_room, id, expected_revision}})

  @impl Commit
  def commit(server, commands) when is_list(commands),
    do: GenServer.call(server, {:commit, commands})

  @impl true
  def init(opts) do
    with {:ok, table} <- table(opts),
         {:ok, path} <- path(opts),
         :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, engine} <- open(table, path) do
      {:ok, %{table: table, path: path, engine: engine}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:command, command}, _from, state) do
    case Engine.command(state.engine, command) do
      {:ok, result, engine} -> persist_reply(state, engine, result)
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:commit, commands}, _from, state) do
    case Engine.commit(state.engine, commands) do
      {:ok, results, engine} -> persist_reply(state, engine, results)
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:query, query}, _from, state),
    do: {:reply, Engine.query(state.engine, query), state}

  @impl true
  def terminate(_reason, state) do
    _ = :dets.sync(state.table)
    _ = :dets.close(state.table)
    :ok
  end

  defp persist_reply(state, engine, result) do
    case persist(state.table, engine) do
      :ok ->
        {:reply, {:ok, result}, %{state | engine: engine}}

      {:insert_error, reason} ->
        {:reply, {:error, {:storage_write_failed, reason}}, state}

      {:sync_error, reason} ->
        error = {:storage_sync_failed, reason}
        {:stop, error, {:error, error}, %{state | engine: engine}}
    end
  end

  defp persist(table, engine) do
    case :dets.insert(table, {@snapshot_key, @format_version, engine}) do
      :ok -> sync(table)
      {:error, reason} -> {:insert_error, reason}
    end
  end

  defp sync(table) do
    case :dets.sync(table) do
      :ok -> :ok
      {:error, reason} -> {:sync_error, reason}
    end
  end

  defp open(table, path) do
    case :dets.open_file(table,
           file: String.to_charlist(path),
           type: :set,
           auto_save: :infinity,
           repair: true
         ) do
      {:ok, ^table} ->
        case load(table) do
          {:ok, engine} ->
            {:ok, engine}

          {:error, _reason} = error ->
            _ = :dets.close(table)
            error
        end

      {:error, reason} ->
        {:error, {:storage_open_failed, reason}}

      other ->
        {:error, {:storage_open_failed, other}}
    end
  end

  defp load(table) do
    case :dets.lookup(table, @snapshot_key) do
      [] ->
        {:ok, Engine.new()}

      [{@snapshot_key, version, engine}] when version in @readable_versions ->
        Engine.restore(engine)

      [{@snapshot_key, version, _engine}] when is_integer(version) ->
        {:error, {:unsupported_storage_version, version}}

      _other ->
        {:error, :invalid_storage_snapshot}
    end
  end

  defp table(opts) do
    case Keyword.fetch(opts, :table) do
      {:ok, table} when is_atom(table) and table not in [nil, true, false] -> {:ok, table}
      _other -> {:error, :invalid_storage_table}
    end
  end

  defp path(opts) do
    case Keyword.fetch(opts, :path) do
      {:ok, path} when is_binary(path) and path != "" -> {:ok, Path.expand(path)}
      _other -> {:error, :invalid_storage_path}
    end
  end
end
