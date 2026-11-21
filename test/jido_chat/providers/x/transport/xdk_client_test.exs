defmodule Jido.Chat.X.Transport.XdkClientTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.X.Transport.XdkClient

  test "requires an explicit XDK client for each operation" do
    assert_raise ArgumentError, ~r/missing :xdk_client/, fn ->
      XdkClient.send_dm("u1", "hello", [])
    end

    assert_raise ArgumentError, ~r/missing :xdk_client/, fn ->
      XdkClient.send_conversation_message("c1", "hello", [])
    end

    assert_raise ArgumentError, ~r/missing :xdk_client/, fn ->
      XdkClient.delete_dm_event("m1", [])
    end

    assert_raise ArgumentError, ~r/missing :xdk_client/, fn ->
      XdkClient.fetch_dm_event("m1", [])
    end

    assert_raise ArgumentError, ~r/missing :xdk_client/, fn ->
      XdkClient.fetch_conversation_messages("c1", [])
    end
  end

  test "rejects old client aliases and filters query input before XDK" do
    assert_raise ArgumentError, ~r/missing :xdk_client/, fn ->
      XdkClient.fetch_dm_event("m1",
        client: :not_an_xdk_struct,
        cursor: "next",
        limit: 20,
        ignored: :value
      )
    end

    assert_raise FunctionClauseError, fn ->
      XdkClient.fetch_conversation_messages("c1",
        xdk_client: :not_an_xdk_struct,
        cursor: "next",
        limit: 20,
        expansions: ["sender_id"],
        ignored: :value
      )
    end
  end

  test "maps operations and query options through XDK without external I/O" do
    {listen_socket, port} = start_http_server(self(), 5)
    finch = :"Jido.Chat.X.TransportTest.Finch.#{System.unique_integer([:positive])}"
    start_supervised!({Finch, name: finch})
    client = Xdk.new(base_url: "http://127.0.0.1:#{port}", finch: finch)

    assert {:ok, _} = XdkClient.send_dm("u1", "hello", xdk_client: client)
    assert {:ok, _} = XdkClient.send_conversation_message("c1", "hello", xdk_client: client)
    assert :ok = XdkClient.delete_dm_event("m1", xdk_client: client)

    assert {:ok, _} =
             XdkClient.fetch_dm_event("m1",
               xdk_client: client,
               dm_event_fields: ["id", "text"],
               cursor: "ignored-for-one",
               limit: 10,
               ignored: :value
             )

    assert {:ok, _} =
             XdkClient.fetch_conversation_messages("c1",
               xdk_client: client,
               cursor: "next page",
               limit: 20,
               expansions: ["sender_id"],
               ignored: :value
             )

    assert_receive {:http_request, "POST /2/dm_conversations/with/u1/messages HTTP/1.1", first}
    assert first =~ ~s({"text":"hello"})

    assert_receive {:http_request, "POST /2/dm_conversations/c1/messages HTTP/1.1", second}
    assert second =~ ~s({"text":"hello"})
    assert_receive {:http_request, "DELETE /2/dm_events/m1 HTTP/1.1", _}

    assert_receive {:http_request, fetch_line, fetch_request}
    assert fetch_line =~ "GET /2/dm_events/m1?"
    assert fetch_request =~ "dm_event.fields=id%2Ctext"
    refute fetch_request =~ "pagination_token"
    refute fetch_request =~ "max_results"
    refute fetch_request =~ "ignored"

    assert_receive {:http_request, page_line, page_request}
    assert page_line =~ "GET /2/dm_conversations/c1/dm_events?"
    assert page_request =~ "pagination_token=next+page"
    assert page_request =~ "max_results=20"
    assert page_request =~ "expansions=sender_id"
    refute page_request =~ "ignored"

    :ok = :gen_tcp.close(listen_socket)
  end

  defp start_http_server(owner, request_count) do
    {:ok, listen_socket} =
      :gen_tcp.listen(0, [:binary, active: false, packet: :raw, reuseaddr: true])

    {:ok, {_address, port}} = :inet.sockname(listen_socket)

    {:ok, _task} =
      Task.start_link(fn ->
        Enum.each(1..request_count, fn _ -> serve_once(listen_socket, owner) end)
      end)

    {listen_socket, port}
  end

  defp serve_once(listen_socket, owner) do
    {:ok, socket} = :gen_tcp.accept(listen_socket, 5_000)
    request = read_request(socket, "")
    [request_line | _] = String.split(request, "\r\n")
    send(owner, {:http_request, request_line, request})

    body = Jason.encode!(%{"data" => %{"id" => "ok"}})

    response =
      "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n#{body}"

    :ok = :gen_tcp.send(socket, response)
    :ok = :gen_tcp.close(socket)
  end

  defp read_request(socket, acc) do
    case complete_request(acc) do
      true ->
        acc

      false ->
        {:ok, data} = :gen_tcp.recv(socket, 0, 5_000)
        read_request(socket, acc <> data)
    end
  end

  defp complete_request(request) do
    case :binary.match(request, "\r\n\r\n") do
      {headers_end, 4} ->
        headers_size = headers_end + 4
        headers = binary_part(request, 0, headers_size)

        content_length =
          case Regex.run(~r/content-length: (\d+)/i, headers) do
            [_, length] -> String.to_integer(length)
            _ -> 0
          end

        byte_size(request) - headers_size >= content_length

      :nomatch ->
        false
    end
  end
end
