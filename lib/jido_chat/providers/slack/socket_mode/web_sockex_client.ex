defmodule Jido.Chat.Slack.SocketMode.WebSockexClient do
  @moduledoc """
  WebSocket client implementation for Slack Socket Mode backed by `WebSockex`.
  """

  @compile {:no_warn_undefined, WebSockex}

  if Code.ensure_loaded?(WebSockex), do: @behaviour(WebSockex)

  require Logger

  alias Jido.Chat.Providers.Dependencies

  @behaviour Jido.Chat.Slack.SocketMode.SocketClient

  def connect(url, owner, opts \\ [])
      when is_binary(url) and is_pid(owner) and is_list(opts) do
    ws_opts =
      opts
      |> Keyword.drop([:headers])
      |> Keyword.put_new(:async, true)
      |> Keyword.put_new(:handle_initial_conn_failure, true)
      |> maybe_put_extra_headers(normalize_headers(opts[:headers]))

    with :ok <- Dependencies.slack_socket() do
      WebSockex.start(url, __MODULE__, %{owner: owner}, ws_opts)
    end
  end

  def send_text(socket, payload) when is_binary(payload),
    do: cast(socket, {:send_text, payload})

  def close(socket), do: cast(socket, :close)

  defp cast(socket, message) do
    with :ok <- Dependencies.slack_socket() do
      WebSockex.cast(socket, message)
    end
  end

  @doc false
  def handle_connect(_conn, state) do
    send(state.owner, {:socket_mode, self(), :connected})
    {:ok, state}
  end

  @doc false
  def handle_frame({:text, payload}, state) do
    send(state.owner, {:socket_mode, self(), {:text, payload}})
    {:ok, state}
  end

  def handle_frame({:binary, payload}, state) do
    send(state.owner, {:socket_mode, self(), {:binary, payload}})
    {:ok, state}
  end

  def handle_frame(_frame, state), do: {:ok, state}

  @doc false
  def handle_cast({:send_text, payload}, state), do: {:reply, {:text, payload}, state}

  def handle_cast(:close, state), do: {:close, state}

  def handle_cast(_message, state), do: {:ok, state}

  @doc false
  def handle_disconnect(status, state) do
    send(state.owner, {:socket_mode, self(), {:disconnected, status.reason}})
    {:ok, state}
  end

  @doc false
  def handle_ping(:ping, state), do: {:reply, :pong, state}
  def handle_ping({:ping, payload}, state), do: {:reply, {:pong, payload}, state}

  @doc false
  def handle_pong(_frame, state), do: {:ok, state}

  @doc false
  def handle_info(message, state) do
    Logger.error("No handle_info/2 clause in #{__MODULE__} provided for #{inspect(message)}")
    {:ok, state}
  end

  @doc false
  def terminate(_reason, _state), do: :ok

  @doc false
  def code_change(_old_vsn, state, _extra), do: {:ok, state}

  @doc false
  def child_spec(state), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [state]}}

  @doc false
  def child_spec(conn_info, state), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [conn_info, state]}}

  defp normalize_headers(nil), do: []

  defp normalize_headers(headers) when is_map(headers) do
    Enum.map(headers, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp normalize_headers(headers) when is_list(headers) do
    Enum.map(headers, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp maybe_put_extra_headers(opts, []), do: opts
  defp maybe_put_extra_headers(opts, headers), do: Keyword.put(opts, :extra_headers, headers)
end
