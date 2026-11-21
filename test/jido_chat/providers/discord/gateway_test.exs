defmodule Jido.Chat.Discord.GatewayTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Discord.Gateway

  test "Mint connection can be closed before the remote socket opens" do
    Process.flag(:trap_exit, true)
    assert {:ok, pid} = Gateway.open("wss://127.0.0.1:9", [])
    ref = Process.monitor(pid)
    assert :ok = Gateway.close(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000
  end

  test "unconnected and unupgraded sockets reject protocol operations" do
    state = %Gateway{owner: self(), request_ref: make_ref()}
    assert {:reply, {:error, :not_connected}, ^state} = Gateway.handle_call(:upgrade, nil, state)

    assert {:reply, {:error, :unknown_stream}, ^state} =
             Gateway.handle_call({:send_frame, make_ref(), {:text, "hello"}}, nil, state)

    assert {:reply, {:error, :not_upgraded}, ^state} =
             Gateway.handle_call({:send_frame, state.request_ref, {:text, "hello"}}, nil, state)

    assert_receive {:gateway_error, _, :not_upgraded}
    assert {:noreply, ^state} = Gateway.handle_info(:unrelated, state)
    assert :ok = Gateway.terminate(:normal, state)
  end

  test "upgrade preserves query options and replays a coalesced first Gateway event" do
    {state, peer} = connection("wss://localhost/gateway?compress=zlib-stream")
    {state, key} = request_upgrade(state, peer)
    payload = Jason.encode!(%{"op" => 10, "d" => %{"heartbeat_interval" => 45_000}})
    first_frame = <<0x81, byte_size(payload), payload::binary>>
    response = upgrade_response(key) <> first_frame
    assert {:noreply, upgraded} = Gateway.handle_info(socket_message(state, peer, response), state)
    ref = state.request_ref
    assert_receive {:gateway_upgrade, _, ^ref}
    assert_receive {:gateway_ws, _, ^ref, {:text, ^payload}}
    assert upgraded.websocket != nil
    assert upgraded.upgrade_data == ""
    assert upgraded.status == nil
    assert upgraded.response_headers == nil
    assert {:ok, closed} = Gateway.terminate(:normal, upgraded)
    refute Mint.HTTP.open?(closed)
  end

  test "upgraded socket delivers events and close frames and answers heartbeat pings" do
    {state, peer} = upgraded_connection()
    ref = state.request_ref
    payload = Jason.encode!(%{"op" => 11})
    frames = <<0x81, byte_size(payload), payload::binary, 0x89, 1, 42, 0x82, 1, 0>>
    assert {:noreply, state} = Gateway.handle_info(socket_message(state, peer, frames), state)
    assert_receive {:gateway_ws, _, ^ref, {:text, ^payload}}
    assert {:ok, pong} = :gen_tcp.recv(peer, 0, 1_000)
    assert {10, <<42>>} = client_frame(pong)

    assert {:reply, :ok, state} = Gateway.handle_call({:send_frame, ref, {:text, "identify"}}, nil, state)
    assert {:ok, sent} = :gen_tcp.recv(peer, 0, 1_000)
    assert {1, "identify"} = client_frame(sent)
    assert {:noreply, ^state} = Gateway.handle_info(:unrelated, state)

    assert {:noreply, _state} = Gateway.handle_info(socket_message(state, peer, <<0x88, 2, 1000::16>>), state)
    assert_receive {:gateway_ws, _, ^ref, {:close, 1000, ""}}
  end

  test "a failed HTTP upgrade is reported without marking the socket upgraded" do
    {state, peer} = connection("wss://localhost")
    {state, _key} = request_upgrade(state, peer)
    response = "HTTP/1.1 403 Forbidden\r\ncontent-length: 0\r\n\r\n"
    assert {:noreply, rejected} = Gateway.handle_info(socket_message(state, peer, response), state)
    assert_receive {:gateway_error, _, :invalid_upgrade_response}
    assert rejected.websocket == nil
  end

  test "a bad upgrade nonce and a closed transport produce owner errors" do
    {state, peer} = connection("wss://localhost")
    {state, _key} = request_upgrade(state, peer)
    assert {:noreply, rejected} = Gateway.handle_info(socket_message(state, peer, upgrade_response("wrong")), state)
    assert_receive {:gateway_error, _, :invalid_nonce}
    assert rejected.websocket == nil

    socket = Mint.HTTP.get_socket(state.conn)
    :gen_tcp.close(peer)
    assert_receive {:tcp_closed, ^socket} = message
    assert {:stop, :normal, _state} = Gateway.handle_info(message, rejected)
    assert_receive {:gateway_error, _, %Mint.TransportError{reason: :closed}}
  end

  defp connection(url) do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_address, port}} = :inet.sockname(listener)
    owner = self()

    spawn_link(fn ->
      {:ok, peer} = :gen_tcp.accept(listener)
      :ok = :gen_tcp.controlling_process(peer, owner)
      send(owner, {:peer, peer})
    end)

    {:ok, conn} = Mint.HTTP1.connect(:http, "127.0.0.1", port, mode: :active)
    assert_receive {:peer, peer}

    on_exit(fn ->
      :gen_tcp.close(listener)
      :gen_tcp.close(peer)
    end)

    {%Gateway{owner: self(), uri: URI.parse(url), conn: conn, websocket_module: Mint.WebSocket}, peer}
  end

  defp request_upgrade(state, peer) do
    assert {:reply, ref, state} = Gateway.handle_call(:upgrade, nil, state)
    assert is_reference(ref)
    assert {:ok, request} = :gen_tcp.recv(peer, 0, 1_000)
    [request_line | _] = String.split(request, "\r\n")
    ["GET", path, "HTTP/1.1"] = String.split(request_line, " ")
    uri = URI.parse(path)
    assert uri.path == (state.uri.path || "/")
    query = URI.decode_query(uri.query)
    assert query["v"] == "10"
    assert query["encoding"] == "json"
    if state.uri.query, do: assert(query["compress"] == "zlib-stream")
    [_, key] = Regex.run(~r/sec-websocket-key: ([^\r]+)/i, request)
    # The local peer uses plain TCP. Production open/2 always uses verified TLS.
    conn = Mint.HTTP.put_private(state.conn, :scheme, :ws)
    {%{state | conn: conn}, key}
  end

  defp upgraded_connection do
    {state, peer} = connection("wss://localhost")
    {state, key} = request_upgrade(state, peer)
    assert {:noreply, state} = Gateway.handle_info(socket_message(state, peer, upgrade_response(key)), state)
    assert_receive {:gateway_upgrade, _, _}
    {state, peer}
  end

  defp upgrade_response(key) do
    accept = :crypto.hash(:sha, key <> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11") |> Base.encode64()

    "HTTP/1.1 101 Switching Protocols\r\nconnection: Upgrade\r\nupgrade: websocket\r\nsec-websocket-accept: #{accept}\r\n\r\n"
  end

  defp socket_message(state, peer, data) do
    socket = Mint.HTTP.get_socket(state.conn)
    :ok = :gen_tcp.send(peer, data)
    assert_receive {:tcp, ^socket, _data} = message, 1_000
    message
  end

  defp client_frame(<<_fin::1, _rsv::3, opcode::4, 1::1, length::7, mask::binary-size(4), data::binary-size(length)>>) do
    decoded =
      data
      |> :binary.bin_to_list()
      |> Enum.with_index()
      |> Enum.map(fn {byte, index} -> Bitwise.bxor(byte, :binary.at(mask, rem(index, 4))) end)
      |> :binary.list_to_bin()

    {opcode, decoded}
  end
end
