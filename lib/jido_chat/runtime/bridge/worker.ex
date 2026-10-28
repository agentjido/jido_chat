defmodule Jido.Chat.Runtime.Bridge.Worker do
  @moduledoc false
  use GenServer

  alias Jido.Chat.Runtime.Storage
  alias Jido.Chat.Runtime.Storage.{Commit, Links, Outbox}

  @terminal [:completed, :failed, :unknown]

  @doc false
  @spec start_link(map()) :: GenServer.on_start()
  def start_link(data) do
    GenServer.start_link(__MODULE__, data, name: {:global, {__MODULE__, data.runtime, data.account_id}})
  end

  @doc false
  @spec server(module(), String.t()) :: {:global, term()}
  def server(runtime, account_id), do: {:global, {__MODULE__, runtime, account_id}}

  @doc false
  @spec data(GenServer.server()) :: map()
  def data(server), do: GenServer.call(server, :data)

  @doc false
  @spec get_work(GenServer.server(), String.t()) :: {:ok, map() | nil} | {:error, term()}
  def get_work(server, id), do: GenServer.call(server, {:get_work, id})

  @doc false
  @spec enqueue(GenServer.server(), map()) :: :ok | {:error, term()}
  def enqueue(server, work), do: GenServer.call(server, {:enqueue, work})

  @doc false
  @spec recover(GenServer.server()) :: :ok | {:error, term()}
  def recover(server), do: GenServer.call(server, :recover)

  @doc false
  @spec finish(GenServer.server(), String.t(), :completed | :failed, map() | nil) ::
          :ok | {:error, term()}
  def finish(server, request_id, outcome, result), do: GenServer.call(server, {:finish, request_id, outcome, result})

  @doc false
  @spec status(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def status(server), do: GenServer.call(server, :status)

  @impl true
  def init(data) do
    with :ok <- Storage.validate(data.storage, [Outbox, Links, Commit]) do
      Process.flag(:trap_exit, true)

      state =
        Map.merge(data, %{
          queue: :queue.new(),
          queued: MapSet.new(),
          active: %{}
        })

      {:ok, state}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:data, _from, state), do: {:reply, public_data(state), state}

  def handle_call({:get_work, id}, _from, state),
    do: {:reply, fetch_work(state, id), state}

  def handle_call({:enqueue, work}, _from, state) do
    with :ok <- validate_work(work, state.account_id),
         work = Map.put_new(work, :status, :pending),
         {:ok, stored} <- outbox(state, :put_work, [work]),
         {:ok, state} <- schedule(stored, state) do
      {:reply, :ok, dispatch(state)}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:recover, _from, state) do
    next = schedule_pending(state)
    {:reply, :ok, dispatch(next)}
  end

  def handle_call({:finish, request_id, outcome, result}, _from, state) do
    {:reply, finish_work(state, request_id, outcome, result), state}
  end

  def handle_call(:status, _from, state) do
    reply =
      with {:ok, work} <- outbox(state, :list_work, [state.account_id, []]) do
        counts = Enum.frequencies_by(work, & &1.status)

        {:ok,
         %{
           account_id: state.account_id,
           total: length(work),
           pending: Map.get(counts, :pending, 0),
           claimed: Map.get(counts, :claimed, 0),
           submitted: Map.get(counts, :submitted, 0),
           completed: Map.get(counts, :completed, 0),
           failed: Map.get(counts, :failed, 0),
           unknown: Map.get(counts, :unknown, 0)
         }}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    case Map.pop(state.active, ref) do
      {nil, _active} ->
        {:noreply, state}

      {work_id, active} ->
        record_execution(state, work_id, result)
        {:noreply, dispatch(%{state | active: active})}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.active, ref) do
      {nil, _active} ->
        {:noreply, state}

      {work_id, active} ->
        mark_interrupted(state, work_id)
        {:noreply, dispatch(%{state | active: active})}
    end
  end

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  defp schedule_pending(state) do
    case outbox(state, :list_work, [state.account_id, [status: :pending]]) do
      {:ok, work} ->
        Enum.reduce(work, state, fn item, current ->
          case schedule(item, current) do
            {:ok, next} -> next
            {:error, _} -> current
          end
        end)

      {:error, _} ->
        state
    end
  end

  defp schedule(%{status: status}, state) when status in @terminal, do: {:ok, state}

  defp schedule(%{id: id}, state) do
    cond do
      id in Map.values(state.active) or MapSet.member?(state.queued, id) ->
        {:ok, state}

      :queue.len(state.queue) >= state.queue_limit ->
        {:error, :provider_work_queue_full}

      true ->
        {:ok,
         %{
           state
           | queue: :queue.in(id, state.queue),
             queued: MapSet.put(state.queued, id)
         }}
    end
  end

  defp dispatch(state) when map_size(state.active) >= state.limit, do: state

  defp dispatch(state) do
    case :queue.out(state.queue) do
      {:empty, _} ->
        state

      {{:value, id}, queue} ->
        state = %{state | queue: queue, queued: MapSet.delete(state.queued, id)}

        with {:ok, %{status: :pending}} <- outbox(state, :get_work, [id]),
             {:ok, claimed} <-
               outbox(state, :update_work, [id, :pending, %{status: :claimed}]) do
          task = Task.async(fn -> execute(claimed, state) end)
          dispatch(%{state | active: Map.put(state.active, task.ref, id)})
        else
          _ -> dispatch(state)
        end
    end
  end

  defp execute(%{kind: :inbound} = work, state) do
    with {:ok, _} <- update(state.storage, work.id, :claimed, %{status: :submitted}),
         {:ok, _, _} <-
           Jido.call(state.jido, work.room, work.signal, context: %{actor: state.account_ref}) do
      {:completed, work.link}
    else
      {:error, reason} -> {:unknown, safe_reason(reason)}
    end
  catch
    :exit, reason -> {:unknown, safe_reason(reason)}
  end

  defp execute(%{kind: :outbound} = work, state) do
    case Jido.resolve_agent(state.jido, state.account_ref) do
      {:ok, server} ->
        with {:ok, _} <- update(state.storage, work.id, :claimed, %{status: :submitted}),
             {:ok, _, _} <- Jido.AgentServer.call(server, work.signal) do
          :submitted
        else
          {:error, reason} -> {:unknown, safe_reason(reason)}
        end

      _ ->
        {:pending, :account_unavailable}
    end
  catch
    :exit, _reason -> {:pending, :account_unavailable}
  end

  defp record_execution(state, work_id, {:completed, link}) do
    commit(state, [
      {:put_link, link},
      {:update_work, work_id, :submitted, %{status: :completed, result: link}}
    ])
  end

  defp record_execution(state, work_id, :submitted), do: fetch_work(state, work_id)

  defp record_execution(state, work_id, {:pending, reason}) do
    update(state.storage, work_id, :claimed, %{status: :pending, last_error: reason})
  end

  defp record_execution(state, work_id, {:unknown, reason}) do
    transition_to_unknown(state, work_id, reason)
  end

  defp finish_work(state, request_id, :completed, result) when is_map(result) do
    with {:ok, %{kind: :outbound, status: :submitted} = work} <- fetch_work(state, request_id),
         external_id when is_binary(external_id) <- get_in(result, ["result", "id"]),
         link = %{
           account_id: work.account_id,
           mapping: work.mapping,
           local_message_id: work.local_message_id,
           external_room_id: work.external_room_id,
           external_message_id: external_id,
           direction: :outbound
         },
         {:ok, _} <-
           commit(state, [
             {:put_link, link},
             {:update_work, request_id, :submitted, %{status: :completed, result: result}}
           ]) do
      :ok
    else
      {:ok, nil} -> {:error, :work_not_found}
      _ -> {:error, :invalid_provider_completion}
    end
  end

  defp finish_work(state, request_id, :failed, result) when is_map(result) do
    status = if result["outcome"] == "unknown", do: :unknown, else: :failed

    case update(state.storage, request_id, :submitted, %{
           status: status,
           last_error: %{"code" => result["code"], "outcome" => result["outcome"]}
         }) do
      {:ok, _} -> :ok
      {:error, :work_not_found} -> {:error, :work_not_found}
      {:error, _} -> {:error, :invalid_provider_completion}
    end
  end

  defp finish_work(_state, _request_id, _outcome, _result),
    do: {:error, :invalid_provider_completion}

  defp mark_interrupted(state, work_id) do
    case fetch_work(state, work_id) do
      {:ok, %{status: :claimed}} ->
        update(state.storage, work_id, :claimed, %{status: :pending, last_error: :worker_exit})

      {:ok, %{status: :submitted}} ->
        update(state.storage, work_id, :submitted, %{status: :unknown, last_error: :worker_exit})

      _ ->
        :ok
    end
  end

  defp transition_to_unknown(state, work_id, reason) do
    case fetch_work(state, work_id) do
      {:ok, %{status: status}} when status in [:claimed, :submitted] ->
        update(state.storage, work_id, status, %{
          status: if(status == :claimed, do: :pending, else: :unknown),
          last_error: reason
        })

      _ ->
        :ok
    end
  end

  defp validate_work(%{id: id, account_id: account_id, kind: kind}, expected)
       when is_binary(id) and id != "" and account_id == expected and
              kind in [:inbound, :outbound],
       do: :ok

  defp validate_work(_, _), do: {:error, :invalid_provider_work}

  defp public_data(state) do
    Map.take(state, [
      :runtime,
      :storage,
      :account_id,
      :account_ref,
      :client_id,
      :client_source,
      :jido,
      :mappings
    ])
  end

  defp fetch_work(state, id), do: outbox(state, :get_work, [id])

  defp outbox(state, function, args) do
    {adapter, resource} = state.storage
    apply(adapter, function, [resource | args])
  end

  defp update({adapter, resource}, id, expected, changes),
    do: apply(adapter, :update_work, [resource, id, expected, changes])

  defp commit(state, commands) do
    {adapter, resource} = state.storage
    apply(adapter, :commit, [resource, commands])
  end

  defp safe_reason(reason) when reason in [:account_unavailable, :not_authorized], do: reason
  defp safe_reason(_), do: :operation_failed
end
