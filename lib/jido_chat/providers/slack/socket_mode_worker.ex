defmodule Jido.Chat.Slack.SocketModeWorker do
  @moduledoc """
  Connection worker for Slack Socket Mode envelopes.

  The worker opens a Socket Mode connection and emits inner payloads through
  `sink_mfa`. It acknowledges an envelope only after the sink accepts it.
  """

  use GenServer

  alias Jido.Chat.Providers.Dependencies
  alias Jido.Chat.Slack.InteractionResponse
  alias Jido.Chat.Slack.SocketMode.{ReqClient, WebSockexClient}

  @type sink_mfa :: {module(), atom(), [term()]}

  @type state :: %{
          sink_mfa: sink_mfa(),
          sink_opts: keyword(),
          app_token: String.t(),
          open_client: module(),
          open_client_opts: keyword(),
          socket_client: module(),
          socket_client_opts: keyword(),
          response_builder: term(),
          reconnect_interval_ms: pos_integer(),
          max_backoff_ms: pos_integer(),
          backoff_ms: pos_integer(),
          path_prefix: String.t(),
          socket: term() | nil,
          socket_monitor_ref: reference() | nil,
          reconnect_timer_ref: reference() | nil
        }

  @doc "Starts a Slack Socket Mode worker."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    with :ok <- check_open_client(Keyword.get(opts, :open_client, ReqClient), opts[:open_client_opts] || []),
         :ok <- check_socket_client(Keyword.get(opts, :socket_client, WebSockexClient)) do
      GenServer.start_link(__MODULE__, opts)
    end
  end

  defp check_open_client(ReqClient, opts), do: Dependencies.req(Keyword.get(opts, :req, Req))
  defp check_open_client(_custom, _opts), do: :ok

  defp check_socket_client(WebSockexClient), do: Dependencies.slack_socket()
  defp check_socket_client(_custom), do: :ok

  @impl true
  def init(opts) do
    Process.flag(:sensitive, true)
    sink_mfa = Keyword.fetch!(opts, :sink_mfa)

    app_token =
      opts[:app_token] ||
        raise(ArgumentError, "missing Slack app token; pass :app_token option")

    reconnect_interval_ms = normalize_pos_integer(opts[:reconnect_interval_ms], 250)

    state = %{
      sink_mfa: sink_mfa,
      sink_opts: Keyword.get(opts, :sink_opts, []),
      app_token: app_token,
      open_client: Keyword.get(opts, :open_client, ReqClient),
      open_client_opts: Keyword.get(opts, :open_client_opts, []),
      socket_client: Keyword.get(opts, :socket_client, WebSockexClient),
      socket_client_opts: Keyword.get(opts, :socket_client_opts, []),
      response_builder: opts[:response_builder] || opts[:slack_response_builder],
      reconnect_interval_ms: reconnect_interval_ms,
      max_backoff_ms: normalize_pos_integer(opts[:max_backoff_ms], 5_000),
      backoff_ms: reconnect_interval_ms,
      path_prefix: normalize_path_prefix(opts[:path_prefix] || "/socket_mode"),
      socket: nil,
      socket_monitor_ref: nil,
      reconnect_timer_ref: nil
    }

    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def format_status(status) do
    Map.new(status, fn
      {:state, _state} -> {:state, :redacted}
      {:message, _message} -> {:message, :redacted}
      {:reason, reason} when is_atom(reason) -> {:reason, reason}
      {:reason, _reason} -> {:reason, :redacted}
      {:log, _log} -> {:log, []}
      {:dictionary, _dictionary} -> {:dictionary, []}
      entry -> entry
    end)
  end

  @impl true
  def handle_info(:connect, %{socket: nil} = state) do
    {:noreply, connect_socket(%{state | reconnect_timer_ref: nil})}
  end

  def handle_info(:connect, state) do
    {:noreply, %{state | reconnect_timer_ref: nil}}
  end

  def handle_info({:socket_mode, socket, :connected}, %{socket: socket} = state) do
    {:noreply, %{state | backoff_ms: state.reconnect_interval_ms}}
  end

  def handle_info({:socket_mode, socket, {:text, payload}}, %{socket: socket} = state) do
    {:noreply, handle_socket_payload(state, payload)}
  end

  def handle_info({:socket_mode, socket, {:binary, _payload}}, %{socket: socket} = state) do
    {:noreply, state}
  end

  def handle_info({:socket_mode, socket, {:disconnected, _reason}}, %{socket: socket} = state) do
    {:noreply, schedule_reconnect(clear_socket(state))}
  end

  def handle_info(
        {:DOWN, ref, :process, socket, _reason},
        %{socket_monitor_ref: ref, socket: socket} = state
      ) do
    {:noreply, schedule_reconnect(clear_socket(state))}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp connect_socket(state) do
    case state.open_client.open_socket(state.app_token, state.open_client_opts) do
      {:ok, url} ->
        case state.socket_client.connect(url, self(), state.socket_client_opts) do
          {:ok, socket} ->
            monitor_ref = if is_pid(socket), do: Process.monitor(socket), else: nil
            %{state | socket: socket, socket_monitor_ref: monitor_ref}

          {:error, _reason} ->
            schedule_reconnect(state)
        end

      {:error, _reason} ->
        schedule_reconnect(state)
    end
  end

  defp handle_socket_payload(state, payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, envelope} when is_map(envelope) ->
        handle_envelope(state, envelope, payload)

      _other ->
        state
    end
  end

  defp handle_socket_payload(state, _payload), do: state

  defp handle_envelope(state, envelope, raw_payload) do
    case map_get(envelope, [:type, "type"]) do
      "hello" ->
        state

      "disconnect" ->
        state
        |> acknowledge_envelope(envelope, nil)
        |> close_socket()
        |> clear_socket()
        |> schedule_reconnect(0)

      _other ->
        route_payload_envelope(state, envelope, raw_payload)
    end
  end

  defp route_payload_envelope(state, envelope, raw_payload) do
    case map_get(envelope, [:payload, "payload"]) do
      payload when is_map(payload) ->
        sink_result =
          invoke_sink(state.sink_mfa, payload, build_sink_opts(state, envelope, raw_payload))

        case sink_result do
          :ok -> acknowledge_envelope(state, envelope, nil)
          {:ok, _} -> acknowledge_envelope(state, envelope, sink_result)
          {:reply, _} -> acknowledge_envelope(state, envelope, sink_result)
          _ -> state
        end

      _payload ->
        acknowledge_envelope(state, envelope, nil)
    end
  end

  defp acknowledge_envelope(%{socket: nil} = state, _envelope, _sink_result), do: state

  defp acknowledge_envelope(state, envelope, sink_result) do
    ack_payload =
      InteractionResponse.socket_ack_payload(envelope, sink_result, response_builder_opts(state))

    case Map.get(ack_payload, "envelope_id") do
      envelope_id when is_binary(envelope_id) ->
        _ =
          state.socket_client.send_text(
            state.socket,
            Jason.encode!(ack_payload)
          )

        state

      _other ->
        state
    end
  end

  defp build_sink_opts(state, envelope, raw_payload) do
    Keyword.merge(
      state.sink_opts,
      mode: :payload,
      method: "SOCKET",
      path: socket_path(state.path_prefix, map_get(envelope, [:type, "type"])),
      raw_body: raw_payload,
      request_metadata: %{
        source: :socket_mode,
        socket_envelope: envelope,
        socket_envelope_id: map_get(envelope, [:envelope_id, "envelope_id"]),
        socket_envelope_type: map_get(envelope, [:type, "type"]),
        accepts_response_payload: map_get(envelope, [:accepts_response_payload, "accepts_response_payload"]) == true
      }
    )
  end

  defp response_builder_opts(%{response_builder: nil}), do: []
  defp response_builder_opts(%{response_builder: builder}), do: [response_builder: builder]

  defp invoke_sink({module, function, base_args}, payload, opts)
       when is_atom(module) and is_atom(function) and is_list(base_args) and is_list(opts) do
    apply(module, function, base_args ++ [payload, opts])
  end

  defp invoke_sink(_sink_mfa, _payload, _opts), do: {:error, :invalid_sink_mfa}

  defp schedule_reconnect(state, delay_ms \\ nil)

  defp schedule_reconnect(state, delay_ms) do
    delay = delay_ms || min(state.backoff_ms, state.max_backoff_ms)

    state = cancel_reconnect_timer(state)

    timer_ref = Process.send_after(self(), :connect, delay)

    %{
      state
      | reconnect_timer_ref: timer_ref,
        backoff_ms: next_backoff(state, delay)
    }
  end

  defp next_backoff(state, 0), do: state.reconnect_interval_ms

  defp next_backoff(state, delay) do
    min(max(delay * 2, state.reconnect_interval_ms), state.max_backoff_ms)
  end

  defp close_socket(%{socket: nil} = state), do: state

  defp close_socket(state) do
    _ = state.socket_client.close(state.socket)
    state
  end

  defp clear_socket(state) do
    state
    |> maybe_demonitor_socket()
    |> Map.put(:socket, nil)
    |> Map.put(:socket_monitor_ref, nil)
  end

  defp maybe_demonitor_socket(%{socket_monitor_ref: nil} = state), do: state

  defp maybe_demonitor_socket(state) do
    Process.demonitor(state.socket_monitor_ref, [:flush])
    state
  end

  defp cancel_reconnect_timer(%{reconnect_timer_ref: nil} = state), do: state

  defp cancel_reconnect_timer(state) do
    Process.cancel_timer(state.reconnect_timer_ref)
    %{state | reconnect_timer_ref: nil}
  end

  defp socket_path(path_prefix, type) do
    String.trim_trailing(path_prefix, "/") <> "/" <> socket_path_segment(type)
  end

  defp socket_path_segment(type) when is_binary(type) do
    type
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
    |> case do
      "" -> "event"
      value -> value
    end
  end

  defp socket_path_segment(_type), do: "event"

  defp normalize_path_prefix(path_prefix) when is_binary(path_prefix) do
    normalized =
      path_prefix
      |> String.trim()
      |> case do
        "" ->
          "/socket_mode"

        value ->
          if String.starts_with?(value, "/"), do: value, else: "/" <> value
      end

    if normalized == "/", do: "/socket_mode", else: normalized
  end

  defp normalize_path_prefix(_path_prefix), do: "/socket_mode"

  defp normalize_pos_integer(value, default)
  defp normalize_pos_integer(nil, default), do: default
  defp normalize_pos_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp normalize_pos_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp normalize_pos_integer(_value, default), do: default

  defp map_get(map, keys) when is_map(map) and is_list(keys) do
    Enum.find_value(keys, fn
      key when is_binary(key) ->
        Map.get(map, key) ||
          try do
            Map.get(map, String.to_existing_atom(key))
          rescue
            ArgumentError -> nil
          end

      key when is_atom(key) ->
        Map.get(map, key) || Map.get(map, Atom.to_string(key))

      key ->
        Map.get(map, key)
    end)
  end
end
