defmodule Jido.Chat.Sensor do
  @moduledoc """
  A receive-only process with a replaceable source and Dispatch target.

      Jido.Chat.Sensor.start_link(
        client: client,
        source: Jido.Chat.Telegram.Source,
        emit: "jido.chat.**",
        interval: 1_000,
        dispatch: {:pid, target: self()}
      )

  Starting a Client does not start a Sensor. The host owns this process.
  Sources can repeat input. Fixed size hashes of the last 1,024 accepted event
  identities are kept in memory to suppress repeats within a running process.
  There is no durable cursor or durable push receipt. The source can provide a global identity.
  A restart can admit an event again.
  """
  use GenServer
  require Logger

  @doc "Starts an explicit, host-owned Sensor."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    with {:ok, state} <- settings(opts) do
      name =
        if function_exported?(state.source, :key, 2) do
          case state.source.key(state.client, state.options) do
            nil -> []
            key -> [name: {:global, {__MODULE__, state.source, key}}]
          end
        else
          []
        end

      GenServer.start_link(__MODULE__, state, name)
    end
  end

  defp settings(opts) do
    with true <- Keyword.keyword?(opts),
         %Jido.Chat.Client{} = client <- opts[:client],
         source when is_atom(source) and not is_nil(source) <- opts[:source],
         true <- Code.ensure_loaded?(source),
         true <- valid_source?(source),
         mode <- source.mode(),
         types when is_list(types) <- source.signal_types(),
         emit <- opts[:emit],
         true <- Jido.Chat.Plugin.Patterns.valid?(emit, types),
         interval when is_integer(interval) and interval > 0 <-
           Keyword.get_lazy(opts, :interval, fn -> poll_interval(source, Keyword.get(opts, :options, [])) end),
         options <- Keyword.get(opts, :options, []),
         true <- Keyword.keyword?(options),
         rooms <- Keyword.get(opts, :rooms, :all),
         true <- rooms == :all or (is_list(rooms) and Enum.all?(rooms, &is_binary/1)),
         {:ok, dispatch} <- Jido.Signal.Dispatch.validate_opts(opts[:dispatch]) do
      {:ok,
       %{
         client: client,
         catalog: Jido.Chat.catalog(client),
         source: source,
         mode: mode,
         worker: nil,
         timer: nil,
         types: types,
         emit: emit,
         interval: interval,
         options: options,
         rooms: rooms,
         dispatch: dispatch,
         cursor: nil,
         provider: :unknown,
         status_target: opts[:status_target],
         seen: MapSet.new(),
         order: :queue.new()
       }}
    else
      _ -> {:error, :invalid_sensor_options}
    end
  rescue
    _ -> {:error, :invalid_sensor_options}
  end

  @doc "Checks the required callbacks for a source's selected mode."
  @spec valid_source?(module()) :: boolean()
  def valid_source?(source) do
    with true <- is_atom(source) and not is_nil(source),
         {:module, _} <- Code.ensure_compiled(source),
         true <- function_exported?(source, :signal_types, 0),
         true <- function_exported?(source, :mode, 0) do
      case source.mode() do
        :poll -> function_exported?(source, :read, 3)
        :push -> function_exported?(source, :start_link, 3)
        _ -> false
      end
    else
      _ -> false
    end
  end

  @doc "Admits a batch from a push source through validation and Dispatch."
  @spec push(GenServer.server(), [Jido.Signal.t()], timeout()) :: :ok | {:error, atom()}
  def push(sensor, signals, timeout \\ 5_000),
    do: GenServer.call(sensor, {:push, signals}, timeout)

  @doc "Returns local process status and the last observed input status. This is not a provider readiness check."
  @spec status(GenServer.server()) :: map()
  def status(sensor), do: GenServer.call(sensor, :status)

  @impl true
  def init(%{mode: :poll} = state), do: {:ok, schedule(report(state))}

  def init(%{mode: :push} = state) do
    Process.flag(:trap_exit, true)

    case state.source.start_link(state.client, self(), state.options) do
      {:ok, worker} when is_pid(worker) ->
        Process.link(worker)
        {:ok, report(%{state | worker: worker})}

      {:error, _reason} ->
        {:stop, :source_start_failed}
    end
  end

  @impl true
  def format_status(status) do
    Map.new(status, fn
      {:state, state} -> {:state, Map.take(state, [:source, :mode])}
      {:reason, reason} when is_atom(reason) -> {:reason, reason}
      {:reason, _} -> {:reason, :sensor_failure}
      {:message, _} -> {:message, :redacted}
      {:log, _} -> {:log, []}
      {:dictionary, _} -> {:dictionary, []}
      entry -> entry
    end)
  end

  @impl true
  def handle_call(:status, _from, state),
    do: {:reply, %{process: :running, provider: state.provider}, state}

  def handle_call({:push, signals}, _from, %{mode: :push} = state) when is_list(signals) do
    case deliver(signals, %{state | provider: :input_observed}) do
      {:ok, accepted} -> {:reply, :ok, report(accepted)}
      {:error, accepted} -> {:reply, {:error, :input_rejected}, report(accepted)}
    end
  end

  def handle_call({:push, _}, _from, state),
    do: {:reply, {:error, :invalid_push}, state}

  @impl true
  def handle_info({:EXIT, worker, reason}, %{worker: worker} = state),
    do: {:stop, {:source_exit, source_exit_reason(reason)}, state}

  def handle_info(:poll, %{mode: :push} = state), do: {:noreply, state}

  def handle_info(:poll, state) do
    if state.timer, do: Process.cancel_timer(state.timer)

    next =
      case state.source.read(state.client, state.cursor, state.options) do
        {:ok, signals, cursor} when is_list(signals) ->
          case deliver(signals, %{state | provider: :read_succeeded}) do
            {:ok, accepted} -> %{accepted | cursor: cursor}
            {:error, accepted} -> accepted
          end

        {:error, _reason} ->
          Logger.warning("Chat Sensor read failed")
          %{state | provider: :read_failed}
      end

    {:noreply, schedule(report(next))}
  end

  defp deliver(signals, state) do
    Enum.reduce_while(signals, {:ok, state}, fn signal, {:ok, current} ->
      case selected(signal, current) do
        :skip ->
          {:cont, {:ok, current}}

        {:ok, signal} ->
          key = :crypto.hash(:sha256, :erlang.term_to_iovec({signal.type, signal.data["item_id"] || signal.id}))

          if MapSet.member?(current.seen, key) do
            {:cont, {:ok, current}}
          else
            case Jido.Signal.Dispatch.dispatch(signal, current.dispatch) do
              :ok -> {:cont, {:ok, remember(current, key)}}
              {:error, _} -> {:halt, {:error, current}}
            end
          end

        :invalid ->
          {:halt, {:error, current}}
      end
    end)
  end

  defp selected(%Jido.Signal{data: data} = signal, state) when is_map(data) do
    cond do
      signal.type not in state.types ->
        :invalid

      signal.source != state.client.source ->
        :invalid

      not Jido.Chat.Plugin.Patterns.selected?(signal.type, state.emit) ->
        :skip

      true ->
        with {:ok, validated} <- Jido.Chat.Signal.Policy.validate(state.catalog, signal) do
          if state.rooms == :all or validated.data["room_id"] in state.rooms, do: {:ok, validated}, else: :skip
        else
          _ -> :invalid
        end
    end
  end

  defp selected(_, _), do: :invalid

  defp remember(state, key) do
    seen = MapSet.put(state.seen, key)
    order = :queue.in(key, state.order)

    {seen, order} =
      if MapSet.size(seen) > 1_024 do
        {{:value, oldest}, rest} = :queue.out(order)
        {MapSet.delete(seen, oldest), rest}
      else
        {seen, order}
      end

    %{state | seen: seen, order: order}
  end

  @impl true
  def terminate(_reason, %{worker: worker}) when is_pid(worker) do
    monitor = Process.monitor(worker)
    Process.exit(worker, :shutdown)

    receive do
      {:DOWN, ^monitor, :process, ^worker, _reason} -> :ok
    after
      1_000 ->
        Process.exit(worker, :kill)
        Process.demonitor(monitor, [:flush])
        :ok
    end
  end

  def terminate(_reason, _state), do: :ok

  defp report(%{status_target: {target, connection}} = state) do
    GenServer.cast(target, {:sensor_status, connection, self(), state.provider})
    state
  end

  defp report(state), do: state

  defp poll_interval(source, options) do
    if function_exported?(source, :poll_interval, 1), do: source.poll_interval(options), else: 1_000
  end

  defp source_exit_reason(reason) when is_atom(reason), do: reason
  defp source_exit_reason(_reason), do: :source_failure

  defp schedule(state), do: %{state | timer: Process.send_after(self(), :poll, state.interval)}
end
