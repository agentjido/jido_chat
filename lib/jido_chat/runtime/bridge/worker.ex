defmodule Jido.Chat.Runtime.Bridge.Worker do
  @moduledoc false
  use GenServer

  alias Jido.Chat.Runtime.Storage
  alias Jido.Chat.Runtime.Storage.{Commit, Links, Outbox}

  @work_state_fields [:status, :last_error, :result, :lease_owner, :lease_expires_at]
  @recovery_retry_ms 1_000

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
  @spec admit(GenServer.server(), map()) :: :ok | {:error, term()}
  def admit(server, work), do: GenServer.call(server, {:admit, [work]})

  @doc false
  @spec admit_many(GenServer.server(), [map()]) :: :ok | {:error, term()}
  def admit_many(server, work), do: GenServer.call(server, {:admit, work})

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

  @impl true
  def init(data) do
    with :ok <- Storage.validate(data.storage, [Outbox, Links, Commit]) do
      Process.flag(:trap_exit, true)

      state =
        Map.merge(data, %{
          queue: :queue.new(),
          queued: MapSet.new(),
          active: %{},
          settlements: %{},
          lease_owner: lease_owner(),
          recovery_timer: nil
        })

      {:ok, state, {:continue, :recover}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:data, _from, state), do: {:reply, public_data(state), state}

  def handle_call({:get_work, id}, _from, state),
    do: {:reply, fetch_work(state, id), state}

  def handle_call({:admit, work}, _from, state) do
    case admit_work(state, work) do
      {:ok, _stored} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:enqueue, work}, _from, state) do
    with {:ok, [stored]} <- admit_work(state, [work]),
         {:ok, state} <- schedule(stored, state) do
      {:reply, :ok, drive(state)}
    else
      {:error, :provider_work_queue_full} -> {:reply, :ok, drive(state)}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:recover, _from, state) do
    case recover_now(state) do
      {:ok, next} -> {:reply, :ok, next}
      {:error, reason, next} -> {:reply, {:error, reason}, next}
    end
  end

  def handle_call({:finish, request_id, outcome, result}, _from, state) do
    {:reply, finish_work(state, request_id, outcome, result), state}
  end

  @impl true
  def handle_continue(:recover, state) do
    case recover_now(state) do
      {:ok, next} -> {:noreply, next}
      {:error, _reason, next} -> {:noreply, next}
    end
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    case Map.pop(state.active, ref) do
      {nil, _active} ->
        {:noreply, state}

      {work_id, active} ->
        next = %{state | active: active}
        {:noreply, settle(next, work_id, result)}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.active, ref) do
      {nil, _active} ->
        {:noreply, state}

      {work_id, active} ->
        next = %{state | active: active}
        {:noreply, settle(next, work_id, :interrupted)}
    end
  end

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  def handle_info(:recover_expired_claims, state) do
    state = %{state | recovery_timer: nil}

    case recover_now(state) do
      {:ok, next} -> {:noreply, next}
      {:error, _reason, next} -> {:noreply, next}
    end
  end

  defp recover_now(state) do
    {state, settlement_error?} = retry_settlements(state)

    case reclaim_expired(state) do
      {:ok, next_expiry} ->
        state = schedule_recovery(state, next_expiry)
        state = drive(state)
        state = if settlement_error?, do: schedule_recovery_retry(state), else: state
        {:ok, state}

      {:error, reason} ->
        {:error, reason, schedule_recovery_retry(state)}
    end
  end

  defp drive(state) do
    case refill(state) do
      {:ok, next} -> dispatch(next)
      {:error, _reason} -> state |> dispatch() |> schedule_recovery_retry()
    end
  end

  defp refill(state) do
    case outbox(state, :list_work, [state.account_id, [status: :pending]]) do
      {:ok, work} ->
        Enum.reduce_while(work, {:ok, state}, fn item, {:ok, current} ->
          case schedule(item, current) do
            {:ok, next} -> {:cont, {:ok, next}}
            {:error, :provider_work_queue_full} -> {:halt, {:ok, current}}
          end
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp schedule(%{status: status}, state) when status != :pending, do: {:ok, state}

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

        dispatch_id(state, id)
    end
  end

  defp dispatch_id(state, id) do
    case outbox(state, :get_work, [id]) do
      {:ok, %{status: :pending}} -> claim_and_start(state, id)
      {:ok, _other} -> dispatch(state)
      {:error, _reason} -> schedule_recovery_retry(state)
    end
  end

  defp claim_and_start(state, id) do
    case outbox(state, :update_work, [
           id,
           :pending,
           %{
             status: :claimed,
             lease_owner: state.lease_owner,
             lease_expires_at: now_ms() + state.lease_ms
           }
         ]) do
      {:ok, claimed} ->
        task = Task.async(fn -> execute(claimed, state) end)
        dispatch(%{state | active: Map.put(state.active, task.ref, id)})

      {:error, :work_conflict} ->
        dispatch(state)

      {:error, _reason} ->
        schedule_recovery_retry(state)
    end
  end

  defp execute(%{kind: :inbound} = work, state) do
    with {:ok, _} <-
           update(state.storage, work.id, :claimed, %{
             status: :submitted,
             lease_owner: nil,
             lease_expires_at: nil
           }),
         {:ok, %Jido.AgentServer.TurnResult{status: :committed}} <-
           Jido.call(state.jido, work.room, work.signal, context: %{actor: state.account_ref}) do
      {:completed, work.link}
    else
      {:error, reason} -> {:unknown, safe_reason(reason)}
      {:ok, result} -> {:unknown, safe_reason(result.error || result.status)}
    end
  catch
    :exit, reason -> {:unknown, safe_reason(reason)}
  end

  defp execute(%{kind: :outbound} = work, state) do
    case Jido.resolve_agent(state.jido, state.account_ref) do
      {:ok, server} ->
        with {:ok, _} <-
               update(state.storage, work.id, :claimed, %{
                 status: :submitted,
                 lease_owner: nil,
                 lease_expires_at: nil
               }),
             {:ok, %Jido.AgentServer.TurnResult{status: :committed}} <- Jido.AgentServer.call(server, work.signal) do
          :submitted
        else
          {:error, reason} -> {:unknown, safe_reason(reason)}
          {:ok, result} -> {:unknown, safe_reason(result.error || result.status)}
        end

      _ ->
        {:pending, :account_unavailable}
    end
  catch
    :exit, _reason -> {:pending, :account_unavailable}
  end

  defp settle(state, work_id, result) do
    case persist_settlement(state, work_id, result) do
      value when value == :ok or (is_tuple(value) and elem(value, 0) == :ok) ->
        next = %{state | settlements: Map.delete(state.settlements, work_id)}

        if retryable_settlement?(result),
          do: next |> dispatch() |> schedule_recovery_retry(),
          else: drive(next)

      _error ->
        state
        |> put_in([:settlements, work_id], result)
        |> dispatch()
        |> schedule_recovery_retry()
    end
  end

  defp retry_settlements(state) do
    Enum.reduce(state.settlements, {state, false}, fn {work_id, result}, {current, failed?} ->
      case persist_settlement(current, work_id, result) do
        value when value == :ok or (is_tuple(value) and elem(value, 0) == :ok) ->
          {%{current | settlements: Map.delete(current.settlements, work_id)}, failed?}

        _error ->
          {current, true}
      end
    end)
  end

  defp persist_settlement(state, work_id, :interrupted), do: mark_interrupted(state, work_id)
  defp persist_settlement(state, work_id, result), do: record_execution(state, work_id, result)

  defp retryable_settlement?({:pending, _reason}), do: true
  defp retryable_settlement?(:interrupted), do: true
  defp retryable_settlement?(_result), do: false

  defp record_execution(state, work_id, {:completed, link}) do
    commit(state, [
      {:put_link, link},
      {:update_work, work_id, :submitted, %{status: :completed, result: link}}
    ])
  end

  defp record_execution(state, work_id, :submitted), do: fetch_work(state, work_id)

  defp record_execution(state, work_id, {:pending, reason}) do
    update(state.storage, work_id, :claimed, %{
      status: :pending,
      last_error: reason,
      lease_owner: nil,
      lease_expires_at: nil
    })
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
        update(state.storage, work_id, :claimed, %{
          status: :pending,
          last_error: :worker_exit,
          lease_owner: nil,
          lease_expires_at: nil
        })

      {:ok, %{status: :submitted}} ->
        update(state.storage, work_id, :submitted, %{
          status: :unknown,
          last_error: :worker_exit,
          lease_owner: nil,
          lease_expires_at: nil
        })

      _ ->
        :ok
    end
  end

  defp transition_to_unknown(state, work_id, reason) do
    case fetch_work(state, work_id) do
      {:ok, %{status: status}} when status in [:claimed, :submitted] ->
        update(state.storage, work_id, status, %{
          status: if(status == :claimed, do: :pending, else: :unknown),
          last_error: reason,
          lease_owner: nil,
          lease_expires_at: nil
        })

      _ ->
        :ok
    end
  end

  defp admit_work(_state, []), do: {:ok, []}

  defp admit_work(state, work) when is_list(work) do
    with {:ok, prepared} <- prepare_admission(state, work),
         commands = for({:new, item} <- prepared, do: {:put_work, item}),
         {:ok, _results} <- commit_admission(state, commands) do
      {:ok, Enum.map(prepared, &elem(&1, 1))}
    end
  end

  defp admit_work(_state, _work), do: {:error, :invalid_provider_work}

  defp prepare_admission(state, work) do
    Enum.reduce_while(work, {:ok, []}, fn item, {:ok, prepared} ->
      with true <- is_map(item),
           pending = Map.put(item, :status, :pending),
           :ok <- validate_work(pending, state.account_id) do
        admission_entry(state, pending, prepared)
      else
        false -> {:halt, {:error, :invalid_provider_work}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, prepared} -> {:ok, Enum.reverse(prepared)}
      error -> error
    end
  end

  defp admission_entry(state, pending, prepared) do
    case fetch_work(state, pending.id) do
      {:ok, nil} ->
        {:cont, {:ok, [{:new, pending} | prepared]}}

      {:ok, stored} ->
        if same_work?(stored, pending),
          do: {:cont, {:ok, [{:existing, stored} | prepared]}},
          else: {:halt, {:error, :storage_conflict}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp commit_admission(_state, []), do: {:ok, []}
  defp commit_admission(state, commands), do: commit(state, commands)

  defp same_work?(stored, candidate) do
    Map.drop(stored, @work_state_fields) == Map.drop(candidate, @work_state_fields)
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

  defp reclaim_expired(state) do
    with {:ok, claimed} <- outbox(state, :list_work, [state.account_id, [status: :claimed]]) do
      Enum.reduce_while(claimed, {:ok, nil}, fn work, {:ok, next_expiry} ->
        if expired_claim?(work, state) do
          case update(state.storage, work.id, :claimed, %{
                 status: :pending,
                 last_error: :claim_expired,
                 lease_owner: nil,
                 lease_expires_at: nil
               }) do
            {:ok, _work} -> {:cont, {:ok, next_expiry}}
            {:error, :work_conflict} -> {:cont, {:ok, next_expiry}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        else
          {:cont, {:ok, next_expiry(next_expiry, work, state)}}
        end
      end)
    end
  end

  defp expired_claim?(work, state) do
    inactive = work.id not in Map.values(state.active)
    expires_at = Map.get(work, :lease_expires_at)
    inactive and (not is_integer(expires_at) or expires_at <= now_ms())
  end

  defp next_expiry(current, work, state) do
    expires_at = Map.get(work, :lease_expires_at)

    if work.id not in Map.values(state.active) and is_integer(expires_at),
      do: min_expiry(current, expires_at),
      else: current
  end

  defp min_expiry(nil, expires_at), do: expires_at
  defp min_expiry(current, expires_at), do: min(current, expires_at)

  defp schedule_recovery(state, nil) do
    cancel_recovery_timer(state.recovery_timer)
    %{state | recovery_timer: nil}
  end

  defp schedule_recovery(state, expires_at) do
    cancel_recovery_timer(state.recovery_timer)
    timer = Process.send_after(self(), :recover_expired_claims, max(expires_at - now_ms(), 0))
    %{state | recovery_timer: timer}
  end

  defp schedule_recovery_retry(state) do
    cancel_recovery_timer(state.recovery_timer)
    timer = Process.send_after(self(), :recover_expired_claims, @recovery_retry_ms)
    %{state | recovery_timer: timer}
  end

  defp cancel_recovery_timer(nil), do: :ok
  defp cancel_recovery_timer(timer), do: Process.cancel_timer(timer, async: false, info: false)

  defp lease_owner do
    [Atom.to_string(node()), Integer.to_string(System.unique_integer([:positive, :monotonic]))]
    |> Enum.join(":")
  end

  defp now_ms, do: System.system_time(:millisecond)

  defp commit(state, commands) do
    {adapter, resource} = state.storage
    apply(adapter, :commit, [resource, commands])
  end

  defp safe_reason(reason) when reason in [:account_unavailable, :not_authorized], do: reason
  defp safe_reason(_), do: :operation_failed
end
