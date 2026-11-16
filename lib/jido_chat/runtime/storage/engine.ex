defmodule Jido.Chat.Runtime.Storage.Engine do
  @moduledoc false

  alias Jido.Chat.Runtime.Storage.Outbox

  @statuses [:pending, :claimed, :submitted, :completed, :failed, :unknown]

  @type t :: %__MODULE__{
          links_local: map(),
          links_external: map(),
          work: map()
        }

  defstruct links_local: %{},
            links_external: %{},
            work: %{}

  @doc false
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc false
  @spec restore(term()) :: {:ok, t()} | {:error, :invalid_storage_snapshot}
  def restore(%__MODULE__{} = state) do
    valid =
      is_map(state.links_local) and is_map(state.links_external) and is_map(state.work)

    if valid, do: {:ok, state}, else: {:error, :invalid_storage_snapshot}
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

  def query(_state, _query), do: {:error, :invalid_storage_query}

  defp compatible(values, key, value) do
    case Map.get(values, key) do
      nil -> :ok
      ^value -> :ok
      _other -> {:error, :storage_conflict}
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
  defp valid_id(_value), do: {:error, :invalid_id}

  defp status_filter(opts) when is_list(opts) do
    case Keyword.get(opts, :status) do
      nil -> {:ok, nil}
      value when value in @statuses -> {:ok, value}
      _other -> {:error, :invalid_status}
    end
  end

  defp status_filter(_opts), do: {:error, :invalid_options}
end
