defmodule Jido.Chat.Runtime.Storage.Memory do
  @moduledoc """
  Process-explicit in-memory implementation of all Runtime storage capabilities.

  The host starts and supervises this process. Data survives callers and account
  Agent restarts, but it does not survive this process or VM restart.
  """

  use GenServer

  alias Jido.Chat.Message
  alias Jido.Chat.Runtime.Storage.Outbox

  @statuses [:pending, :claimed, :submitted, :completed, :failed, :unknown]

  @behaviour Jido.Chat.Runtime.Storage.History
  @behaviour Jido.Chat.Runtime.Storage.Links
  @behaviour Jido.Chat.Runtime.Storage.Outbox
  @behaviour Jido.Chat.Runtime.Storage.Rooms
  @behaviour Jido.Chat.Runtime.Storage.Commit

  @type state :: %{
          messages: map(),
          next_sequence: non_neg_integer(),
          links_local: map(),
          links_external: map(),
          work: map(),
          rooms: map(),
          members: map()
        }

  @doc "Starts an empty memory storage resource."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.take(opts, [:name]))
  end

  @impl Jido.Chat.Runtime.Storage.History
  def append_message(server, %Message{} = message),
    do: GenServer.call(server, {:command, {:append_message, message}})

  @impl Jido.Chat.Runtime.Storage.History
  def list_messages(server, room_id, opts \\ []),
    do: GenServer.call(server, {:list_messages, room_id, opts})

  @impl Jido.Chat.Runtime.Storage.Links
  def put_link(server, link), do: GenServer.call(server, {:command, {:put_link, link}})

  @impl Jido.Chat.Runtime.Storage.Links
  def link_for_local(server, account_id, local_message_id),
    do: GenServer.call(server, {:link_for_local, account_id, local_message_id})

  @impl Jido.Chat.Runtime.Storage.Links
  def link_for_external(server, account_id, external_room_id, external_message_id),
    do: GenServer.call(server, {:link_for_external, account_id, external_room_id, external_message_id})

  @impl Jido.Chat.Runtime.Storage.Outbox
  def put_work(server, work), do: GenServer.call(server, {:command, {:put_work, work}})

  @impl Jido.Chat.Runtime.Storage.Outbox
  def get_work(server, id), do: GenServer.call(server, {:get_work, id})

  @impl Jido.Chat.Runtime.Storage.Outbox
  def list_work(server, account_id, opts \\ []),
    do: GenServer.call(server, {:list_work, account_id, opts})

  @impl Jido.Chat.Runtime.Storage.Outbox
  def update_work(server, id, expected_status, changes),
    do: GenServer.call(server, {:command, {:update_work, id, expected_status, changes}})

  @impl Jido.Chat.Runtime.Storage.Rooms
  def put_room(server, room), do: GenServer.call(server, {:command, {:put_room, room}})

  @impl Jido.Chat.Runtime.Storage.Rooms
  def get_room(server, id), do: GenServer.call(server, {:get_room, id})

  @impl Jido.Chat.Runtime.Storage.Rooms
  def put_members(server, id, members),
    do: GenServer.call(server, {:command, {:put_members, id, members}})

  @impl Jido.Chat.Runtime.Storage.Rooms
  def get_members(server, id), do: GenServer.call(server, {:get_members, id})

  @impl Jido.Chat.Runtime.Storage.Commit
  def commit(server, commands) when is_list(commands), do: GenServer.call(server, {:commit, commands})

  @impl true
  def init(:ok) do
    {:ok,
     %{
       messages: %{},
       next_sequence: 0,
       links_local: %{},
       links_external: %{},
       work: %{},
       rooms: %{},
       members: %{}
     }}
  end

  @impl true
  def handle_call({:command, command}, _from, state) do
    case apply_command(command, state) do
      {:ok, result, state} -> {:reply, {:ok, result}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:commit, commands}, _from, state) do
    case apply_commands(commands, state) do
      {:ok, results, state} -> {:reply, {:ok, results}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:list_messages, room_id, opts}, _from, state) do
    reply =
      with :ok <- valid_id(room_id),
           {:ok, limit} <- limit(opts) do
        messages =
          state.messages
          |> Map.get(room_id, %{})
          |> Map.values()
          |> Enum.sort_by(& &1.sequence)
          |> Enum.map(& &1.message)
          |> take_limit(limit)

        {:ok, messages}
      end

    {:reply, reply, state}
  end

  def handle_call({:link_for_local, account_id, local_message_id}, _from, state) do
    reply =
      with :ok <- valid_id(account_id),
           :ok <- valid_id(local_message_id) do
        {:ok, Map.get(state.links_local, {account_id, local_message_id})}
      end

    {:reply, reply, state}
  end

  def handle_call({:link_for_external, account_id, room_id, message_id}, _from, state) do
    reply =
      with :ok <- valid_id(account_id),
           :ok <- valid_id(room_id),
           :ok <- valid_id(message_id) do
        {:ok, Map.get(state.links_external, {account_id, room_id, message_id})}
      end

    {:reply, reply, state}
  end

  def handle_call({:get_work, id}, _from, state) do
    reply = if valid_id(id) == :ok, do: {:ok, Map.get(state.work, id)}, else: {:error, :invalid_work_id}
    {:reply, reply, state}
  end

  def handle_call({:list_work, account_id, opts}, _from, state) do
    reply =
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

    {:reply, reply, state}
  end

  def handle_call({:get_room, id}, _from, state) do
    reply = if valid_id(id) == :ok, do: {:ok, Map.get(state.rooms, id)}, else: {:error, :invalid_room_id}
    {:reply, reply, state}
  end

  def handle_call({:get_members, id}, _from, state) do
    reply = if valid_id(id) == :ok, do: {:ok, Map.get(state.members, id, [])}, else: {:error, :invalid_room_id}
    {:reply, reply, state}
  end

  defp apply_commands(commands, state) do
    Enum.reduce_while(commands, {:ok, [], state}, fn command, {:ok, results, current} ->
      case apply_command(command, current) do
        {:ok, result, next} -> {:cont, {:ok, [result | results], next}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, results, next} -> {:ok, Enum.reverse(results), next}
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_command({:append_message, %Message{} = message}, state) do
    room_messages = Map.get(state.messages, message.room_id, %{})

    case Map.get(room_messages, message.id) do
      nil ->
        sequence = state.next_sequence + 1
        entry = %{sequence: sequence, message: message}
        messages = Map.put(state.messages, message.room_id, Map.put(room_messages, message.id, entry))
        {:ok, message, %{state | messages: messages, next_sequence: sequence}}

      %{message: ^message} ->
        {:ok, message, state}

      _ ->
        {:error, :message_conflict}
    end
  end

  defp apply_command({:put_link, link}, state) when is_map(link) do
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

  defp apply_command({:put_work, work}, state) when is_map(work) do
    with :ok <- valid_work(work),
         :ok <- compatible(state.work, work.id, work) do
      {:ok, work, %{state | work: Map.put(state.work, work.id, work)}}
    end
  end

  defp apply_command({:update_work, id, expected_status, changes}, state) when is_map(changes) do
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
      %{status: _} -> {:error, :work_conflict}
      false -> {:error, :invalid_work_transition}
      {:error, _} = error -> error
      _ -> {:error, :invalid_work_update}
    end
  end

  defp apply_command({:put_room, room}, state) when is_map(room) do
    with id when not is_nil(id) <- Map.get(room, :id),
         :ok <- valid_id(id),
         :ok <- compatible(state.rooms, id, room) do
      {:ok, room, %{state | rooms: Map.put(state.rooms, id, room)}}
    else
      _ -> {:error, :invalid_room}
    end
  end

  defp apply_command({:put_members, id, members}, state) when is_list(members) do
    with :ok <- valid_id(id),
         true <- Map.has_key?(state.rooms, id),
         true <- length(members) == length(Enum.uniq(members)) do
      {:ok, members, %{state | members: Map.put(state.members, id, members)}}
    else
      false -> {:error, :invalid_members}
      {:error, _} = error -> error
    end
  end

  defp apply_command(_, _state), do: {:error, :invalid_storage_command}

  defp compatible(values, key, value) do
    case Map.get(values, key) do
      nil -> :ok
      ^value -> :ok
      _ -> {:error, :storage_conflict}
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

  defp valid_id(value) when is_binary(value) and value != "", do: :ok
  defp valid_id(_), do: {:error, :invalid_id}

  defp limit(opts) when is_list(opts) do
    case Keyword.get(opts, :limit) do
      nil -> {:ok, nil}
      value when is_integer(value) and value > 0 -> {:ok, value}
      _ -> {:error, :invalid_limit}
    end
  end

  defp limit(_), do: {:error, :invalid_options}

  defp status_filter(opts) when is_list(opts) do
    case Keyword.get(opts, :status) do
      nil -> {:ok, nil}
      value when value in @statuses -> {:ok, value}
      _ -> {:error, :invalid_status}
    end
  end

  defp status_filter(_), do: {:error, :invalid_options}

  defp take_limit(values, nil), do: values
  defp take_limit(values, limit), do: Enum.take(values, limit)
end
