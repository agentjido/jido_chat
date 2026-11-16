defmodule Jido.Chat.Runtime.Storage.Engine do
  @moduledoc false

  alias Jido.Chat.Runtime.Room.Record
  alias Jido.Chat.Runtime.Storage.Outbox

  @statuses [:pending, :claimed, :submitted, :completed, :failed, :unknown]

  @type t :: %__MODULE__{
          links_local: map(),
          links_external: map(),
          work: map(),
          rooms: map()
        }

  defstruct links_local: %{},
            links_external: %{},
            work: %{},
            rooms: %{}

  @doc false
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc false
  @spec restore(term()) :: {:ok, t()} | {:error, :invalid_storage_snapshot}
  def restore(%{__struct__: __MODULE__} = state) do
    rooms = Map.get(state, :rooms, %{})

    valid =
      is_map(Map.get(state, :links_local)) and is_map(Map.get(state, :links_external)) and
        is_map(Map.get(state, :work)) and is_map(rooms) and valid_rooms?(rooms)

    if valid do
      {:ok,
       %__MODULE__{
         links_local: state.links_local,
         links_external: state.links_external,
         work: state.work,
         rooms: rooms
       }}
    else
      {:error, :invalid_storage_snapshot}
    end
  end

  def restore(_state), do: {:error, :invalid_storage_snapshot}

  @doc false
  @spec command(t(), term()) :: {:ok, term(), t()} | {:error, term()}
  def command(state, {:put_link, link}) when is_map(link) do
    with :ok <- valid_link(link),
         local_key = {link.account_id, link.local_message_id},
         external_key = {link.account_id, link.external_room_id, link.external_message_id},
         :ok <- compatible(state.links_local, local_key, link),
         :ok <- compatible(state.links_external, external_key, link) do
      {:ok, link,
       %{
         state
         | links_local: Map.put(state.links_local, local_key, link),
           links_external: Map.put(state.links_external, external_key, link)
       }}
    end
  end

  def command(state, {:put_work, work}) when is_map(work) do
    with :ok <- valid_work(work),
         :ok <- compatible(state.work, work.id, work) do
      {:ok, work, %{state | work: Map.put(state.work, work.id, work)}}
    end
  end

  def command(state, {:update_work, id, expected_status, changes}) when is_map(changes) do
    with :ok <- valid_id(id),
         %{status: ^expected_status} = current <- Map.get(state.work, id),
         next_status when not is_nil(next_status) <- Map.get(changes, :status),
         true <- Outbox.valid_transition?(expected_status, next_status),
         true <- Map.keys(changes) -- [:status, :last_error, :result, :lease_owner, :lease_expires_at] == [],
         next = Map.merge(current, changes),
         :ok <- valid_work(next) do
      {:ok, next, %{state | work: Map.put(state.work, id, next)}}
    else
      nil -> {:error, :work_not_found}
      %{status: _status} -> {:error, :work_conflict}
      false -> {:error, :invalid_work_transition}
      {:error, _reason} = error -> error
      _other -> {:error, :invalid_work_update}
    end
  end

  def command(state, {:insert_room, %Record{} = record}) do
    with {:ok, record} <- Record.new(record),
         :ok <- compatible_room(state.rooms, record.id, record) do
      {:ok, record, %{state | rooms: Map.put(state.rooms, record.id, record)}}
    end
  end

  def command(state, {:update_room, id, expected_revision, %Record{} = record}) do
    with :ok <- valid_room_id(id),
         %Record{revision: ^expected_revision} = current <- Map.get(state.rooms, id),
         {:ok, record} <- Record.new(record),
         :ok <- valid_room_update(id, expected_revision, current, record) do
      {:ok, record, %{state | rooms: Map.put(state.rooms, id, record)}}
    else
      nil -> {:error, :room_not_found}
      %Record{} -> {:error, :room_conflict}
      {:error, _reason} = error -> error
      _other -> {:error, :invalid_room}
    end
  end

  def command(state, {:delete_room, id, expected_revision}) do
    with :ok <- valid_room_id(id),
         %Record{revision: ^expected_revision} <- Map.get(state.rooms, id) do
      {:ok, :ok, %{state | rooms: Map.delete(state.rooms, id)}}
    else
      nil -> {:error, :room_not_found}
      %Record{} -> {:error, :room_conflict}
      {:error, _reason} = error -> error
      _other -> {:error, :invalid_room}
    end
  end

  def command(_state, _command), do: {:error, :invalid_storage_command}

  @doc false
  @spec commit(t(), [term()]) :: {:ok, [term()], t()} | {:error, term()}
  def commit(state, commands) when is_list(commands) do
    commands
    |> Enum.reduce_while({:ok, [], state}, fn command, {:ok, results, current} ->
      case command(current, command) do
        {:ok, result, next} -> {:cont, {:ok, [result | results], next}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, results, next} -> {:ok, Enum.reverse(results), next}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  @spec query(t(), term()) :: {:ok, term()} | {:error, term()}
  def query(state, {:link_for_local, account_id, local_message_id}) do
    with :ok <- valid_id(account_id),
         :ok <- valid_id(local_message_id) do
      {:ok, Map.get(state.links_local, {account_id, local_message_id})}
    end
  end

  def query(state, {:link_for_external, account_id, room_id, message_id}) do
    with :ok <- valid_id(account_id),
         :ok <- valid_id(room_id),
         :ok <- valid_id(message_id) do
      {:ok, Map.get(state.links_external, {account_id, room_id, message_id})}
    end
  end

  def query(state, {:get_work, id}) do
    if valid_id(id) == :ok,
      do: {:ok, Map.get(state.work, id)},
      else: {:error, :invalid_work_id}
  end

  def query(state, {:list_work, account_id, opts}) do
    with :ok <- valid_id(account_id),
         {:ok, status} <- status_filter(opts) do
      work =
        state.work
        |> Map.values()
        |> Enum.filter(&(&1.account_id == account_id))
        |> Enum.filter(&(is_nil(status) or &1.status == status))
        |> Enum.sort_by(& &1.id)

      {:ok, work}
    end
  end

  def query(state, {:get_room, id}) do
    if valid_room_id(id) == :ok,
      do: {:ok, Map.get(state.rooms, id)},
      else: {:error, :invalid_room_id}
  end

  def query(state, {:list_rooms, opts}) do
    with {:ok, query} <- room_query(opts),
         {:ok, cursor} <- room_cursor(state.rooms, query.after) do
      rooms =
        state.rooms
        |> Map.values()
        |> Enum.sort_by(&room_sort_key/1)
        |> after_cursor(cursor)
        |> filter_room_kind(query.kind)
        |> Enum.take(query.limit)

      {:ok, rooms}
    end
  end

  def query(_state, _query), do: {:error, :invalid_storage_query}

  defp compatible(values, key, value) do
    case Map.get(values, key) do
      nil -> :ok
      ^value -> :ok
      _other -> {:error, :storage_conflict}
    end
  end

  defp compatible_room(values, key, value) do
    case compatible(values, key, value) do
      {:error, :storage_conflict} -> {:error, :room_conflict}
      result -> result
    end
  end

  defp valid_link(link) do
    if Enum.all?([:account_id, :local_message_id, :external_room_id, :external_message_id], fn key ->
         valid_id(Map.get(link, key)) == :ok
       end),
       do: :ok,
       else: {:error, :invalid_link}
  end

  defp valid_work(work) do
    if valid_id(Map.get(work, :id)) == :ok and valid_id(Map.get(work, :account_id)) == :ok and
         Map.get(work, :status) in Outbox.statuses(),
       do: :ok,
       else: {:error, :invalid_work}
  end

  defp valid_rooms?(rooms) do
    Enum.all?(rooms, fn
      {id, %Record{id: id} = record} -> match?({:ok, %Record{}}, Record.new(record))
      _entry -> false
    end)
  end

  defp valid_room_update(id, expected_revision, current, record) do
    valid =
      record.id == id and record.schema_version == current.schema_version and
        record.kind == current.kind and record.inserted_at == current.inserted_at and
        record.revision == expected_revision + 1 and
        DateTime.compare(record.updated_at, current.updated_at) in [:eq, :gt]

    if valid, do: :ok, else: {:error, :invalid_room_update}
  end

  defp room_query(opts) when is_list(opts) do
    with true <- Keyword.keyword?(opts),
         keys = Keyword.keys(opts),
         true <- keys == Enum.uniq(keys),
         [] <- keys -- [:kind, :after, :limit],
         {:ok, kind} <- room_kind(Keyword.get(opts, :kind)),
         {:ok, after_id} <- room_after(Keyword.get(opts, :after)),
         {:ok, limit} <- room_limit(Keyword.get(opts, :limit, 100)) do
      {:ok, %{kind: kind, after: after_id, limit: limit}}
    else
      {:error, _reason} = error -> error
      _other -> {:error, :invalid_options}
    end
  end

  defp room_query(_opts), do: {:error, :invalid_options}

  defp room_kind(nil), do: {:ok, nil}
  defp room_kind(kind) when kind in [:direct, :group, :channel, :thread], do: {:ok, kind}
  defp room_kind(_kind), do: {:error, :invalid_room_kind}

  defp room_after(nil), do: {:ok, nil}

  defp room_after(id) do
    case valid_room_id(id) do
      :ok -> {:ok, id}
      {:error, _reason} -> {:error, :invalid_room_cursor}
    end
  end

  defp room_limit(limit) when is_integer(limit) and limit in 1..1_000, do: {:ok, limit}
  defp room_limit(_limit), do: {:error, :invalid_limit}

  defp room_cursor(_rooms, nil), do: {:ok, nil}

  defp room_cursor(rooms, id) do
    case Map.get(rooms, id) do
      %Record{} = record -> {:ok, room_sort_key(record)}
      nil -> {:error, :invalid_room_cursor}
    end
  end

  defp room_sort_key(record),
    do: {DateTime.to_unix(record.inserted_at, :microsecond), record.id}

  defp after_cursor(rooms, nil), do: rooms
  defp after_cursor(rooms, cursor), do: Enum.drop_while(rooms, &(room_sort_key(&1) <= cursor))

  defp filter_room_kind(rooms, nil), do: rooms
  defp filter_room_kind(rooms, kind), do: Enum.filter(rooms, &(&1.kind == kind))

  defp valid_id(value) when is_binary(value) and value != "", do: :ok
  defp valid_id(_value), do: {:error, :invalid_id}

  defp valid_room_id(value), do: Record.valid_id(value, [])

  defp status_filter(opts) when is_list(opts) do
    case Keyword.get(opts, :status) do
      nil -> {:ok, nil}
      value when value in @statuses -> {:ok, value}
      _other -> {:error, :invalid_status}
    end
  end

  defp status_filter(_opts), do: {:error, :invalid_options}
end
