defmodule Jido.Chat.Discord.GatewayWorker do
  @moduledoc false
  use GenServer

  alias Jido.Chat.Discord.{Gateway, Transport.REST}
  alias Jido.Chat.Providers.Dependencies

  @events ~w(MESSAGE_CREATE MESSAGE_UPDATE MESSAGE_DELETE MESSAGE_REACTION_ADD MESSAGE_REACTION_REMOVE INTERACTION_CREATE THREAD_CREATE)

  @doc "Start the linked receive worker for a host Sensor."
  def start_link({%Jido.Chat.Client{credentials: %{token: token}, transport: transport}, _, opts} = args)
      when is_binary(token) and token != "" do
    with :ok <- check_dependency(Keyword.get(opts, :gateway, Gateway)),
         :ok <- check_dependency(transport) do
      GenServer.start_link(__MODULE__, args)
    end
  end

  def start_link(_), do: {:error, :missing_token}

  defp check_dependency(Gateway), do: Dependencies.discord_gateway()
  defp check_dependency(REST), do: Dependencies.req()
  defp check_dependency(_custom), do: :ok

  @impl true
  def init({client, sensor, opts}) do
    Process.flag(:trap_exit, true)
    Process.flag(:sensitive, true)
    monitor = Process.monitor(sensor)

    state = %{
      client: client,
      sensor: sensor,
      monitor: monitor,
      opts: opts,
      gateway: Keyword.get(opts, :gateway, Gateway),
      connection: nil,
      stream: nil,
      session: nil,
      sequence: nil,
      resume_url: nil,
      url: nil,
      heartbeat: nil,
      heartbeat_timer: nil,
      connect_timer: nil,
      reconnect_timer: nil,
      ack: true,
      retry: 0,
      parents: %{}
    }

    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    result =
      if state.url,
        do: {:ok, %{"url" => state.url}},
        else:
          state.client.transport.call(
            state.client.credentials.token,
            :get,
            "/gateway/bot",
            nil,
            state.client.config
          )

    with {:ok, %{"url" => url}} <- result,
         {:ok, pid} <- state.gateway.open(state.resume_url || url, state.opts) do
      timer = Process.send_after(self(), {:connect_timeout, pid}, Keyword.get(state.opts, :connect_timeout, 15_000))
      {:noreply, %{state | connection: pid, url: url, connect_timer: timer, reconnect_timer: nil}}
    else
      {:error, {:rejected, category, _}} when category in [:unauthorized, :forbidden] -> {:stop, category, state}
      _ -> {:noreply, reconnect(state)}
    end
  rescue
    _ -> {:stop, :gateway_failure, state}
  catch
    _, _ -> {:stop, :gateway_failure, state}
  end

  def handle_info({:gateway_up, pid}, %{connection: pid} = s),
    do: {:noreply, %{s | stream: s.gateway.upgrade(pid)}}

  def handle_info({:gateway_upgrade, pid, stream}, %{connection: pid, stream: stream} = s),
    do: {:noreply, s}

  def handle_info({:gateway_ws, pid, stream, {:text, text}}, %{connection: pid, stream: stream} = s) do
    case Jason.decode(text) do
      {:ok, payload} -> safe_packet(payload, s)
      _ -> {:noreply, reconnect(s)}
    end
  end

  def handle_info({:gateway_ws, pid, _, {:close, code, _}}, %{connection: pid} = s)
      when code in [4004, 4010, 4011, 4012, 4013, 4014], do: {:stop, {:gateway_closed, code}, s}

  def handle_info({:gateway_ws, pid, _, {:close, code, _}}, %{connection: pid} = s) when code in [4007, 4009],
    do: {:noreply, reconnect(%{s | session: nil, sequence: nil, resume_url: nil})}

  def handle_info({:gateway_ws, pid, _, :close}, %{connection: pid} = s), do: {:noreply, reconnect(s)}
  def handle_info({:gateway_ws, pid, _, {:close, _, _}}, %{connection: pid} = s), do: {:noreply, reconnect(s)}
  def handle_info({:gateway_down, pid, _}, %{connection: pid} = s), do: {:noreply, reconnect(s)}
  def handle_info({:gateway_error, pid, _}, %{connection: pid} = s), do: {:noreply, reconnect(s)}

  def handle_info({:EXIT, pid, _}, %{connection: pid} = s), do: {:noreply, reconnect(s)}
  def handle_info({:EXIT, pid, reason}, %{sensor: pid} = s), do: {:stop, reason, s}
  def handle_info({:DOWN, ref, :process, _, _}, %{monitor: ref} = s), do: {:stop, :normal, s}
  def handle_info({:connect_timeout, pid}, %{connection: pid} = s), do: {:noreply, reconnect(s)}
  def handle_info({:heartbeat, nil}, %{connection: nil} = s), do: {:noreply, s}
  def handle_info({:heartbeat, pid}, %{connection: pid, ack: false} = s), do: {:noreply, reconnect(s)}

  def handle_info({:heartbeat, pid}, %{connection: pid} = s) do
    send_packet(s, 1, s.sequence)
    {:noreply, %{s | ack: false, heartbeat_timer: Process.send_after(self(), {:heartbeat, s.connection}, s.heartbeat)}}
  end

  def handle_info(_, s), do: {:noreply, s}

  defp safe_packet(payload, state) do
    packet(payload, state)
  rescue
    _ -> {:stop, :gateway_failure, state}
  catch
    _, _ -> {:stop, :gateway_failure, state}
  end

  defp packet(%{"op" => 10, "d" => %{"heartbeat_interval" => interval}}, s)
       when is_integer(interval) and interval > 0 do
    cancel(s.connect_timer)
    timer = Process.send_after(self(), {:heartbeat, s.connection}, trunc(:rand.uniform() * interval))

    if s.session do
      send_packet(s, 6, %{"token" => s.client.credentials.token, "session_id" => s.session, "seq" => s.sequence})
    else
      send_packet(s, 2, %{
        "token" => s.client.credentials.token,
        "intents" => Keyword.get(s.opts, :intents, 46593),
        "properties" => %{"os" => "linux", "browser" => "jido_chat_discord", "device" => "jido_chat_discord"}
      })
    end

    {:noreply, %{s | heartbeat: interval, heartbeat_timer: timer, connect_timer: nil, ack: true}}
  end

  defp packet(%{"op" => 11}, s), do: {:noreply, %{s | ack: true}}

  defp packet(%{"op" => 1}, s) do
    send_packet(s, 1, s.sequence)
    {:noreply, s}
  end

  defp packet(%{"op" => 7}, s), do: {:noreply, reconnect(s)}

  defp packet(%{"op" => 9, "d" => resumable}, s) do
    s = if resumable, do: s, else: %{s | session: nil, sequence: nil, resume_url: nil}
    {:noreply, reconnect(s)}
  end

  defp packet(%{"op" => 0, "t" => "READY", "d" => d, "s" => sequence}, s) do
    bot_id = get_in(d, ["user", "id"])
    client = %{s.client | config: Keyword.put(s.client.config, :bot_id, bot_id)}

    {:noreply,
     %{
       s
       | client: client,
         session: d["session_id"],
         resume_url: d["resume_gateway_url"],
         sequence: sequence,
         retry: 0,
         parents: parents(d["guilds"] || [], s.parents)
     }}
  end

  defp packet(%{"op" => 0, "t" => "GUILD_CREATE", "d" => d, "s" => sequence}, s),
    do: {:noreply, %{s | sequence: sequence, parents: parents([d], s.parents)}}

  defp packet(%{"op" => 0, "t" => kind, "d" => d, "s" => sequence} = event, s) when kind in @events do
    d = if parent = s.parents[d["channel_id"]], do: Map.put(d, "parent_id", parent), else: d
    event = Map.put(event, "d", d)

    with :ok <- capture_interaction(kind, d, s),
         {:ok, delivery} <- Jido.Chat.normalize(s.client, event),
         :ok <- Jido.Chat.Sensor.push(s.sensor, delivery.signals, Keyword.get(s.opts, :push_timeout, 5_000)) do
      parents = if kind == "THREAD_CREATE", do: Map.put(s.parents, d["id"], d["parent_id"]), else: s.parents
      {:noreply, %{s | sequence: sequence, retry: 0, parents: parents}}
    else
      _ -> {:stop, :input_rejected, s}
    end
  catch
    :exit, _ -> {:stop, :input_rejected, s}
  end

  defp packet(%{"op" => 0, "s" => sequence}, s), do: {:noreply, %{s | sequence: sequence, retry: 0}}
  defp packet(_, s), do: {:noreply, s}

  defp capture_interaction("INTERACTION_CREATE", data, s),
    do: Jido.Chat.Discord.Interaction.capture(s.client, data, s.opts[:interaction_sink])

  defp capture_interaction(_, _, _), do: :ok

  defp parents(guilds, acc),
    do:
      Enum.reduce(guilds, acc, fn guild, acc ->
        Enum.reduce(guild["threads"] || [], acc, fn t, acc -> Map.put(acc, t["id"], t["parent_id"]) end)
      end)

  defp send_packet(s, op, data), do: s.gateway.send_frame(s.connection, s.stream, %{"op" => op, "d" => data})

  defp reconnect(s) do
    cancel(s.heartbeat_timer)
    cancel(s.connect_timer)
    close(s)
    cancel(s.reconnect_timer)
    delay = Keyword.get(s.opts, :reconnect_delay, min(1_000 * Integer.pow(2, min(s.retry, 5)), 30_000))
    timer = Process.send_after(self(), :connect, delay)

    %{
      s
      | connection: nil,
        stream: nil,
        ack: true,
        heartbeat_timer: nil,
        connect_timer: nil,
        reconnect_timer: timer,
        retry: s.retry + 1
    }
  end

  defp cancel(nil), do: :ok
  defp cancel(ref), do: Process.cancel_timer(ref)
  defp close(%{connection: nil}), do: :ok
  defp close(s), do: s.gateway.close(s.connection)
  @impl true
  def format_status(status) do
    status = Enum.reduce([:state, :message, :log, :dictionary], status, &Map.put(&2, &1, :redacted))

    case status do
      %{reason: reason}
      when reason in [:normal, :shutdown, :input_rejected, :unauthorized, :forbidden, :gateway_failure] ->
        status

      %{reason: {:gateway_closed, code}} when code in [4004, 4010, 4011, 4012, 4013, 4014] ->
        status

      %{reason: _} ->
        Map.put(status, :reason, :gateway_failure)

      _ ->
        status
    end
  end

  @impl true
  def terminate(_, s) do
    cancel(s.heartbeat_timer)
    cancel(s.connect_timer)
    cancel(s.reconnect_timer)
    close(s)
  end
end
