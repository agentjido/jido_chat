defmodule Jido.Chat.Slack.SocketMode.WebSockexClientTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Slack.SocketMode.WebSockexClient

  test "the default socket handles frames and closes a loopback connection" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, packet: :http_bin, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    on_exit(fn -> :gen_tcp.close(listener) end)

    peer =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 2_000)
        assert {:ok, {:http_request, :GET, {:abs_path, "/socket"}, _}} = :gen_tcp.recv(socket, 0, 2_000)
        headers = read_headers(socket, %{})
        assert headers["x-chat-test"] == "fixture"
        key = Map.fetch!(headers, "sec-websocket-key")
        accept = :crypto.hash(:sha, key <> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11") |> Base.encode64()

        :ok = :inet.setopts(socket, packet: :raw)

        :ok =
          :gen_tcp.send(socket, [
            "HTTP/1.1 101 Switching Protocols\r\n",
            "Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ",
            accept,
            "\r\n\r\n"
          ])

        :ok = :gen_tcp.send(socket, <<0x81, 5, "hello", 0x82, 1, 42, 0x89, 1, 7>>)
        assert {10, <<7>>} = read_client_frame(socket)
        assert {1, "ack"} = read_client_frame(socket)
        assert {8, _} = read_client_frame(socket)
        :ok = :gen_tcp.send(socket, <<0x88, 2, 1000::16>>)
        :ok = :gen_tcp.close(socket)
      end)

    assert {:ok, socket} =
             WebSockexClient.connect("ws://127.0.0.1:#{port}/socket", self(), headers: %{"x-chat-test" => "fixture"})

    assert_receive {:socket_mode, ^socket, :connected}
    ref = Process.monitor(socket)
    assert_receive {:socket_mode, ^socket, {:text, "hello"}}
    assert_receive {:socket_mode, ^socket, {:binary, <<42>>}}
    assert :ok = WebSockexClient.send_text(socket, "ack")
    assert :ok = WebSockexClient.close(socket)
    assert :ok = Task.await(peer)
    assert_receive {:DOWN, ^ref, :process, ^socket, :normal}
  end

  defp read_headers(socket, headers) do
    case :gen_tcp.recv(socket, 0, 2_000) do
      {:ok, {:http_header, _, _, name, value}} ->
        read_headers(socket, Map.put(headers, name |> to_string() |> String.downcase(), value))

      {:ok, :http_eoh} ->
        headers
    end
  end

  defp read_client_frame(socket) do
    {:ok, <<1::1, 0::3, opcode::4, 1::1, length::7, mask::binary-size(4)>>} = :gen_tcp.recv(socket, 6, 2_000)

    payload =
      if length == 0 do
        ""
      else
        {:ok, encoded} = :gen_tcp.recv(socket, length, 2_000)
        repeated = :binary.copy(mask, div(length + 3, 4))
        :crypto.exor(encoded, binary_part(repeated, 0, length))
      end

    {opcode, payload}
  end
end
