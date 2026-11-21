defmodule Jido.Chat.Telegram.TestHTTP do
  @moduledoc false

  @doc false
  @spec serve(pos_integer(), binary(), (String.t() -> term())) :: {term(), binary()}
  def serve(status, body, callback) do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listener)
    parent = self()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5_000)
        request = read_request(socket, "")
        send(parent, {:http_request, request})

        :ok =
          :gen_tcp.send(socket, [
            "HTTP/1.1 #{status} Test\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n",
            body
          ])

        :gen_tcp.close(socket)
      end)

    try do
      result = callback.("http://127.0.0.1:#{port}")
      Task.await(server, 5_000)

      assert_request =
        receive do
          {:http_request, request} -> request
        after
          1_000 -> raise "missing HTTP request"
        end

      {result, assert_request}
    after
      :gen_tcp.close(listener)
      Task.shutdown(server, :brutal_kill)
    end
  end

  defp read_request(socket, data) do
    case String.split(data, "\r\n\r\n", parts: 2) do
      [headers, body] ->
        length =
          case Regex.run(~r/content-length: (\d+)/i, headers) do
            [_, value] -> String.to_integer(value)
            nil -> 0
          end

        if byte_size(body) >= length, do: data, else: read_more(socket, data)

      _ ->
        read_more(socket, data)
    end
  end

  defp read_more(socket, data) do
    {:ok, bytes} = :gen_tcp.recv(socket, 0, 5_000)
    read_request(socket, data <> bytes)
  end
end
