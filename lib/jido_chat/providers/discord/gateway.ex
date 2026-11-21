defmodule Jido.Chat.Discord.Gateway do
  @moduledoc false
  use GenServer

  @compile {:no_warn_undefined, [Mint.HTTP, Mint.HTTP1, Mint.WebSocket]}

  alias Jido.Chat.Providers.Dependencies

  defstruct [
    :owner,
    :uri,
    :conn,
    :request_ref,
    :websocket,
    :websocket_module,
    :status,
    :response_headers,
    upgrade_data: ""
  ]

  @type t :: %__MODULE__{
          owner: pid(),
          uri: URI.t(),
          conn: Mint.HTTP1.t() | nil,
          request_ref: Mint.Types.request_ref() | nil,
          websocket: Mint.WebSocket.t() | nil,
          websocket_module: module(),
          status: Mint.Types.status() | nil,
          response_headers: Mint.Types.headers() | nil,
          upgrade_data: binary()
        }

  @doc "Open a verified TLS Gateway socket."
  def open(url, opts) do
    with :ok <- Dependencies.discord_gateway() do
      websocket_module = Keyword.get(opts, :websocket_module, Mint.WebSocket)
      GenServer.start_link(__MODULE__, {self(), url, websocket_module})
    end
  end

  @doc "Request the Discord JSON WebSocket protocol."
  def upgrade(pid), do: GenServer.call(pid, :upgrade)

  @doc "Send an encoded Gateway protocol frame."
  def send_frame(pid, stream, data),
    do: GenServer.call(pid, {:send_frame, stream, {:text, Jason.encode!(data)}})

  @doc "Close the owned Gateway socket."
  def close(pid) do
    GenServer.stop(pid, :normal)
  catch
    :exit, _reason -> :ok
  end

  @impl true
  def init({owner, url, websocket_module}) do
    Process.flag(:sensitive, true)
    send(self(), :connect)

    {:ok,
     %__MODULE__{
       owner: owner,
       uri: URI.parse(url),
       websocket_module: websocket_module
     }}
  end

  @impl true
  def handle_info(:connect, state) do
    options = [
      transport_opts: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        server_name_indication: String.to_charlist(state.uri.host)
      ]
    ]

    case Mint.HTTP1.connect(:https, state.uri.host, state.uri.port || 443, options) do
      {:ok, conn} ->
        send(state.owner, {:gateway_up, self()})
        {:noreply, %{state | conn: conn}}

      {:error, reason} ->
        send(state.owner, {:gateway_error, self(), reason})
        {:stop, :normal, state}
    end
  end

  def handle_info(message, %{conn: conn} = state) when not is_nil(conn) do
    case Mint.WebSocket.stream(conn, message) do
      {:ok, conn, responses} ->
        {:noreply, handle_responses(%{state | conn: conn}, responses)}

      {:error, conn, reason, responses} ->
        state = handle_responses(%{state | conn: conn}, responses)
        send(state.owner, {:gateway_error, self(), reason})
        {:stop, :normal, state}

      :unknown ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def handle_call(:upgrade, _from, %{conn: nil} = state),
    do: {:reply, {:error, :not_connected}, state}

  def handle_call(:upgrade, _from, state) do
    path = gateway_path(state.uri)

    case Mint.WebSocket.upgrade(:wss, state.conn, path, []) do
      {:ok, conn, request_ref} ->
        {:reply, request_ref, %{state | conn: conn, request_ref: request_ref}}

      {:error, conn, reason} ->
        send(state.owner, {:gateway_error, self(), reason})
        {:reply, {:error, reason}, %{state | conn: conn}}
    end
  end

  def handle_call({:send_frame, stream, _frame}, _from, %{request_ref: request_ref} = state)
      when stream != request_ref,
      do: {:reply, {:error, :unknown_stream}, state}

  def handle_call({:send_frame, _stream, frame}, _from, state) do
    case send_frame_data(state, frame) do
      {:ok, state} ->
        {:reply, :ok, state}

      {:error, state, reason} ->
        send(state.owner, {:gateway_error, self(), reason})
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def terminate(_reason, %{conn: nil}), do: :ok
  def terminate(_reason, state), do: Mint.HTTP.close(state.conn)

  @spec handle_responses(t(), [Mint.Types.response()]) :: t()
  defp handle_responses(state, []), do: state

  defp handle_responses(%{request_ref: ref} = state, [{:status, ref, status} | rest]),
    do: handle_responses(%{state | status: status}, rest)

  defp handle_responses(%{request_ref: ref} = state, [{:headers, ref, headers} | rest]),
    do: handle_responses(%{state | response_headers: headers}, rest)

  defp handle_responses(%{request_ref: ref, websocket: nil} = state, [{:data, ref, data} | rest]),
    do: handle_responses(%{state | upgrade_data: state.upgrade_data <> data}, rest)

  defp handle_responses(
         %{request_ref: ref, status: status, response_headers: headers} = state,
         [{:done, ref} | rest]
       )
       when status == 101 and is_list(headers) do
    case state.websocket_module.new(state.conn, ref, status, headers) do
      {:ok, conn, websocket} ->
        case Mint.HTTP.set_mode(conn, :active) do
          {:ok, conn} ->
            send(state.owner, {:gateway_upgrade, self(), ref})

            responses =
              if state.upgrade_data == "",
                do: rest,
                else: [{:data, ref, state.upgrade_data} | rest]

            handle_responses(
              %{
                state
                | conn: conn,
                  websocket: websocket,
                  status: nil,
                  response_headers: nil,
                  upgrade_data: ""
              },
              responses
            )

          {:error, reason} ->
            send(state.owner, {:gateway_error, self(), reason})
            %{state | conn: conn}
        end

      {:error, conn, reason} ->
        send(state.owner, {:gateway_error, self(), reason})
        %{state | conn: conn}
    end
  end

  defp handle_responses(%{request_ref: ref} = state, [{:done, ref} | rest]) do
    send(state.owner, {:gateway_error, self(), :invalid_upgrade_response})
    handle_responses(state, rest)
  end

  defp handle_responses(%{request_ref: ref, websocket: websocket} = state, [
         {:data, ref, data} | rest
       ])
       when not is_nil(websocket) do
    case Mint.WebSocket.decode(websocket, data) do
      {:ok, websocket, frames} ->
        state
        |> Map.put(:websocket, websocket)
        |> handle_frames(frames)
        |> handle_responses(rest)

      {:error, websocket, reason} ->
        send(state.owner, {:gateway_error, self(), reason})
        %{state | websocket: websocket}
    end
  end

  defp handle_responses(state, [_response | rest]), do: handle_responses(state, rest)

  defp handle_frames(state, frames) do
    Enum.reduce(frames, state, fn
      {:ping, data}, current ->
        case send_frame_data(current, {:pong, data}) do
          {:ok, next} ->
            next

          {:error, next, reason} ->
            send(next.owner, {:gateway_error, self(), reason})
            next
        end

      {:text, text}, current ->
        send(current.owner, {:gateway_ws, self(), current.request_ref, {:text, text}})
        current

      {:close, code, reason}, current ->
        send(current.owner, {:gateway_ws, self(), current.request_ref, {:close, code, reason}})
        current

      :close, current ->
        send(current.owner, {:gateway_ws, self(), current.request_ref, :close})
        current

      _frame, current ->
        current
    end)
  end

  defp send_frame_data(%{websocket: nil} = state, _frame),
    do: {:error, state, :not_upgraded}

  defp send_frame_data(state, frame) do
    case Mint.WebSocket.encode(state.websocket, frame) do
      {:ok, websocket, data} ->
        state = %{state | websocket: websocket}

        case Mint.WebSocket.stream_request_body(state.conn, state.request_ref, data) do
          {:ok, conn} -> {:ok, %{state | conn: conn}}
          {:error, conn, reason} -> {:error, %{state | conn: conn}, reason}
        end

      {:error, websocket, reason} ->
        {:error, %{state | websocket: websocket}, reason}
    end
  end

  defp gateway_path(uri) do
    path = if uri.path in [nil, ""], do: "/", else: uri.path
    query = URI.decode_query(uri.query || "") |> Map.merge(%{"encoding" => "json", "v" => "10"})
    path <> "?" <> URI.encode_query(query)
  end
end
