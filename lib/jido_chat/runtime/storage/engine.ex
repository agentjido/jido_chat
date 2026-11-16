defmodule Jido.Chat.Runtime.Storage.Engine do
  @moduledoc false

  alias Jido.Chat.Runtime.Room.{Declaration, HistoryRecord, Membership, Record}
  alias Jido.Chat.Runtime.Storage.Outbox

  @statuses [:pending, :claimed, :submitted, :completed, :failed, :unknown]

  @type t :: %__MODULE__{
          links_local: map(),
          links_external: map(),
          work: map(),
          rooms: map(),
          room_declarations: map(),
          memberships: map(),
          history: map()
        }

  defstruct links_local: %{},
            links_external: %{},
            work: %{},
            rooms: %{},
            room_declarations: %{},
            memberships: %{},
            history: %{}

  @doc false
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc false
  @spec restore(term()) :: {:ok, t()} | {:error, :invalid_storage_snapshot}
  def restore(%{__struct__: __MODULE__} = state) do
    rooms = Map.get(state, :rooms, %{})
    declarations = Map.get(state, :room_declarations, %{})
    memberships = Map.get(state, :memberships, %{})
    history = Map.get(state, :history, %{})

    valid =
      is_map(Map.get(state, :links_local)) and is_map(Map.get(state, :links_external)) and
        is_map(Map.get(state, :work)) and is_map(rooms) and valid_rooms?(rooms) and
        is_map(declarations) and valid_declarations?(declarations) and
        is_map(memberships) and valid_memberships?(memberships) and
        is_map(history) and valid_history?(history) and unique_history_sequences?(history)

    if valid do
      {:ok,
       %__MODULE__{
         links_local: state.links_local,
         links_external: state.links_external,
         work: state.work,
         rooms: rooms,
         room_declarations: declarations,
         memberships: memberships,
         history: history
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

  def command(state, {:insert_room_declaration, %Declaration{} = declaration}) do
    with {:ok, declaration} <- Declaration.new(declaration),
         :ok <-
           compatible_domain(
             state.room_declarations,
             declaration.room_id,
             declaration,
             :room_declaration_conflict
           ) do
      {:ok, declaration,
       %{state | room_declarations: Map.put(state.room_declarations, declaration.room_id, declaration)}}
    end
  end

  def command(state, {:update_room_declaration, id, expected_revision, %Declaration{} = declaration}) do
    with %Declaration{revision: ^expected_revision} = current <- Map.get(state.room_declarations, id),
         {:ok, declaration} <- Declaration.new(declaration),
         true <-
           declaration.room_id == id and declaration.schema_version == current.schema_version and
             declaration.definition_key == current.definition_key and
             declaration.inserted_at == current.inserted_at and declaration.revision == expected_revision + 1 and
             DateTime.compare(declaration.updated_at, current.updated_at) in [:eq, :gt] do
      {:ok, declaration, %{state | room_declarations: Map.put(state.room_declarations, id, declaration)}}
    else
      nil -> {:error, :room_declaration_not_found}
      %Declaration{} -> {:error, :room_declaration_conflict}
      false -> {:error, :invalid_room_declaration_update}
      {:error, _reason} = error -> error
    end
  end

  def command(state, {:delete_room_declaration, id, expected_revision}) do
    case Map.get(state.room_declarations, id) do
      %Declaration{revision: ^expected_revision, desired: :stopped} ->
        {:ok, :ok, %{state | room_declarations: Map.delete(state.room_declarations, id)}}

      %Declaration{} ->
        {:error, :room_declaration_conflict}

      nil ->
        {:error, :room_declaration_not_found}
    end
  end

  def command(state, {:insert_membership, %Membership{} = membership}) do
    key = {membership.room_id, membership.member_key}

    with {:ok, membership} <- Membership.new(membership),
         :ok <- compatible_domain(state.memberships, key, membership, :membership_conflict) do
      {:ok, membership, %{state | memberships: Map.put(state.memberships, key, membership)}}
    end
  end

  def command(state, {:update_membership, room_id, member_key, expected_revision, %Membership{} = membership}) do
    key = {room_id, member_key}

    with %Membership{revision: ^expected_revision} = current <- Map.get(state.memberships, key),
         {:ok, membership} <- Membership.new(membership),
         true <-
           membership.room_id == room_id and membership.member_key == member_key and
             membership.schema_version == current.schema_version and
             membership.member == current.member and membership.inserted_at == current.inserted_at and
             membership.revision == expected_revision + 1 and
             DateTime.compare(membership.updated_at, current.updated_at) in [:eq, :gt] do
      {:ok, membership, %{state | memberships: Map.put(state.memberships, key, membership)}}
    else
      nil -> {:error, :membership_not_found}
      %Membership{} -> {:error, :membership_conflict}
      false -> {:error, :invalid_membership_update}
      {:error, _reason} = error -> error
    end
  end

  def command(state, {:insert_history, %HistoryRecord{} = record}) do
    key = {record.room_id, record.message_id}

    with {:ok, record} <- HistoryRecord.new(record),
         :ok <- compatible_domain(state.history, key, record, :message_id_conflict),
         :ok <- available_sequence(state.history, record) do
      {:ok, record, %{state | history: Map.put(state.history, key, record)}}
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

  def query(state, {:get_room_declaration, id}),
    do: {:ok, Map.get(state.room_declarations, id)}

  def query(state, :list_room_declarations) do
    {:ok, state.room_declarations |> Map.values() |> Enum.sort_by(& &1.room_id)}
  end

  def query(state, {:get_membership, room_id, member_key}),
    do: {:ok, Map.get(state.memberships, {room_id, member_key})}

  def query(state, {:list_memberships, room_id, opts}) do
    with :ok <- valid_id(room_id),
         {:ok, query} <- membership_query(opts) do
      values =
        state.memberships
        |> Map.values()
        |> Enum.filter(&(&1.room_id == room_id))
        |> Enum.filter(&(is_nil(query.status) or &1.status == query.status))
        |> Enum.sort_by(& &1.member_key)
        |> Enum.drop_while(&(not is_nil(query.after) and &1.member_key <= query.after))
        |> Enum.take(query.limit)

      {:ok, values}
    end
  end

  def query(state, {:get_history, room_id, message_id}),
    do: {:ok, Map.get(state.history, {room_id, message_id})}

  def query(state, {:last_history_sequence, room_id}) do
    with :ok <- valid_id(room_id) do
      sequence =
        state.history
        |> Map.values()
        |> Enum.filter(&(&1.room_id == room_id))
        |> Enum.reduce(0, &max(&1.sequence, &2))

      {:ok, sequence}
    end
  end

  def query(state, {:list_history, room_id, opts}) do
    with :ok <- valid_id(room_id),
         {:ok, query} <- history_query(opts),
         {:ok, before_sequence} <- history_cursor(state.history, room_id, query.before),
         {:ok, after_sequence} <- history_cursor(state.history, room_id, query.after) do
      values =
        state.history
        |> Map.values()
        |> Enum.filter(&(&1.room_id == room_id))
        |> Enum.filter(&(is_nil(query.thread_id) or &1.thread_id == query.thread_id))
        |> Enum.sort_by(& &1.sequence)
        |> filter_history(before_sequence, after_sequence)
        |> take_history(query.limit, before_sequence, query.latest)

      {:ok, values}
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

  defp compatible_domain(values, key, value, conflict) do
    case compatible(values, key, value) do
      {:error, :storage_conflict} -> {:error, conflict}
      result -> result
    end
  end

  defp available_sequence(history, record) do
    conflict =
      Enum.any?(history, fn
        {{room_id, message_id}, value} ->
          room_id == record.room_id and message_id != record.message_id and value.sequence == record.sequence
      end)

    if conflict, do: {:error, :history_sequence_conflict}, else: :ok
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

  defp valid_declarations?(values) do
    Enum.all?(values, fn
      {id, %Declaration{room_id: id} = value} -> match?({:ok, _}, Declaration.new(value))
      _entry -> false
    end)
  end

  defp valid_memberships?(values) do
    Enum.all?(values, fn
      {{room_id, member_key}, %Membership{room_id: room_id, member_key: member_key} = value} ->
        match?({:ok, _}, Membership.new(value))

      _entry ->
        false
    end)
  end

  defp valid_history?(values) do
    Enum.all?(values, fn
      {{room_id, message_id}, %HistoryRecord{room_id: room_id, message_id: message_id} = value} ->
        match?({:ok, _}, HistoryRecord.new(value))

      _entry ->
        false
    end)
  end

  defp unique_history_sequences?(values) do
    keys = Enum.map(values, fn {_key, value} -> {value.room_id, value.sequence} end)
    length(keys) == length(Enum.uniq(keys))
  end

  defp membership_query(opts) when is_list(opts) do
    with true <- Keyword.keyword?(opts),
         keys = Keyword.keys(opts),
         true <- keys == Enum.uniq(keys),
         [] <- keys -- [:status, :after, :limit],
         status when is_nil(status) or status in [:active, :suspended, :revoked] <- Keyword.get(opts, :status),
         after_key when is_nil(after_key) or is_binary(after_key) <- Keyword.get(opts, :after),
         limit when is_integer(limit) and limit in 1..1_000 <- Keyword.get(opts, :limit, 100) do
      {:ok, %{status: status, after: after_key, limit: limit}}
    else
      _ -> {:error, :invalid_options}
    end
  end

  defp membership_query(_opts), do: {:error, :invalid_options}

  defp history_query(opts) when is_list(opts) do
    with true <- Keyword.keyword?(opts),
         keys = Keyword.keys(opts),
         true <- keys == Enum.uniq(keys),
         [] <- keys -- [:before, :after, :thread_id, :limit, :latest],
         before when is_nil(before) or is_binary(before) <- Keyword.get(opts, :before),
         after_id when is_nil(after_id) or is_binary(after_id) <- Keyword.get(opts, :after),
         true <- is_nil(before) or is_nil(after_id),
         thread_id when is_nil(thread_id) or is_binary(thread_id) <- Keyword.get(opts, :thread_id),
         latest when is_boolean(latest) <- Keyword.get(opts, :latest, false),
         true <- not latest or (is_nil(before) and is_nil(after_id)),
         limit when is_integer(limit) and limit in 1..1_000 <- Keyword.get(opts, :limit, 100) do
      {:ok, %{before: before, after: after_id, thread_id: thread_id, latest: latest, limit: limit}}
    else
      _ -> {:error, :invalid_options}
    end
  end

  defp history_query(_opts), do: {:error, :invalid_options}

  defp history_cursor(_history, _room_id, nil), do: {:ok, nil}

  defp history_cursor(history, room_id, message_id) do
    case Map.get(history, {room_id, message_id}) do
      %HistoryRecord{sequence: sequence} -> {:ok, sequence}
      nil -> {:error, :invalid_history_cursor}
    end
  end

  defp filter_history(values, before, after_sequence) do
    Enum.filter(values, fn value ->
      (is_nil(before) or value.sequence < before) and
        (is_nil(after_sequence) or value.sequence > after_sequence)
    end)
  end

  defp take_history(values, limit, before, _latest) when is_integer(before),
    do: Enum.take(values, -limit)

  defp take_history(values, limit, _before, true), do: Enum.take(values, -limit)
  defp take_history(values, limit, _before, false), do: Enum.take(values, limit)

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
