defmodule Jido.Chat.Signal.Transport.JsonRpcClientTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Signal.Transport.JsonRpcClient

  defmodule StubAdapter do
    def run(request) do
      Process.get({Jido.Chat.Signal.Transport.JsonRpcClientTest, :adapter}).(request)
    end
  end

  defp request_options(adapter) do
    Process.put({__MODULE__, :adapter}, adapter)
    [adapter: StubAdapter]
  end

  test "polls receive through the JSON-RPC daemon" do
    test_pid = self()

    adapter = fn request ->
      body = Jason.decode!(request.body)
      send(test_pid, {:rpc_request, request.method, request.url, body, request.options})

      response =
        Req.Response.json(%{
          "jsonrpc" => "2.0",
          "id" => body["id"],
          "result" => [
            %{
              "envelope" => %{
                "sourceNumber" => "+15555550100",
                "timestamp" => 1_776_000_000,
                "dataMessage" => %{"timestamp" => 1_776_000_000, "message" => "hello"}
              }
            }
          ]
        })

      {request, %{response | status: 200}}
    end

    assert {:ok, [payload]} =
             JsonRpcClient.receive_messages(
               "+15555550101",
               endpoint: "http://signal.test/api/v1/rpc",
               receive_timeout_s: 2,
               max_messages: 5,
               req_options: request_options(adapter)
             )

    assert %{"envelope" => %{"dataMessage" => %{"message" => "hello"}}} = payload

    assert_received {:rpc_request, :post, uri, body, options}
    assert URI.to_string(uri) == "http://signal.test/api/v1/rpc"
    assert options.receive_timeout == 15_000
    assert body["method"] == "receive"
    assert body["params"]["account"] == "+15555550101"
    assert body["params"]["timeout"] == 2
    assert body["params"]["maxMessages"] == 5
  end

  test "honors explicit HTTP receive timeout for receive polling" do
    test_pid = self()

    adapter = fn request ->
      send(test_pid, {:rpc_options, request.options})
      {request, %{Req.Response.json(%{"result" => []}) | status: 200}}
    end

    assert {:ok, []} =
             JsonRpcClient.receive_messages(
               nil,
               endpoint: "http://signal.test/api/v1/rpc",
               receive_timeout_s: 30,
               http_receive_timeout_ms: 2_000,
               req_options: request_options(adapter)
             )

    assert_received {:rpc_options, options}
    assert options.receive_timeout == 2_000
  end

  test "keeps all receive items for complete adapter normalization" do
    adapter = fn request ->
      body = Jason.decode!(request.body)

      response =
        Req.Response.json(%{
          "jsonrpc" => "2.0",
          "id" => body["id"],
          "result" => [%{"receiptMessage" => %{}}, nil]
        })

      {request, %{response | status: 200}}
    end

    assert {:ok, [%{"receiptMessage" => %{}}, nil]} =
             JsonRpcClient.receive_messages(
               nil,
               endpoint: "http://signal.test/api/v1/rpc",
               req_options: request_options(adapter)
             )
  end

  test "returns JSON-RPC daemon errors" do
    adapter = fn request ->
      body = Jason.decode!(request.body)

      response =
        Req.Response.json(%{
          "jsonrpc" => "2.0",
          "id" => body["id"],
          "error" => %{"code" => -32_000, "message" => "already receiving"}
        })

      {request, %{response | status: 200}}
    end

    assert {:error, {:signal_rpc_error, 200, %{"code" => -32_000, "message" => "already receiving"}}} =
             JsonRpcClient.receive_messages(
               nil,
               endpoint: "http://signal.test/api/v1/rpc",
               req_options: request_options(adapter)
             )
  end

  test "sends local and data-backed attachments through JSON-RPC" do
    test_pid = self()

    adapter = fn request ->
      body = Jason.decode!(request.body)
      send(test_pid, {:rpc_body, body})

      {request, %{Req.Response.json(%{"result" => %{"timestamp" => 1_776_000_000}}) | status: 200}}
    end

    attachment = %{
      data: "R0lGODlhAQABAAAAACw=",
      filename: "tiny.gif",
      media_type: "image/gif"
    }

    assert {:ok, %{"timestamp" => 1_776_000_000}} =
             JsonRpcClient.send_message(nil, "+15555550100", "gif",
               endpoint: "http://signal.test/api/v1/rpc",
               attachments: [%{path: "/tmp/report.txt"}, attachment],
               req_options: request_options(adapter)
             )

    assert_received {:rpc_body, body}

    assert body["params"]["attachments"] == [
             "/tmp/report.txt",
             "data:image/gif;filename=tiny.gif;base64,R0lGODlhAQABAAAAACw="
           ]
  end

  test "rejects remote attachments before JSON-RPC send" do
    assert {:error, {:unsupported_remote_attachment, "https://example.test/file.txt"}} =
             JsonRpcClient.send_message(nil, "+15555550100", "file",
               endpoint: "http://signal.test/api/v1/rpc",
               attachments: [%{url: "https://example.test/file.txt"}],
               req_options: [
                 adapter: fn request ->
                   flunk("unexpected JSON-RPC request: #{inspect(request)}")
                 end
               ]
             )
  end

  test "sends group replies with explicit account identity" do
    test_pid = self()

    adapter = fn request ->
      body = Jason.decode!(request.body)
      send(test_pid, {:rpc_send_body, body})
      {request, %{Req.Response.json(%{"result" => %{"timestamp" => 1}}) | status: 200}}
    end

    assert {:ok, _} =
             JsonRpcClient.send_message("+15555550101", "group:group-1", "reply",
               endpoint: "http://signal.test/api/v1/rpc",
               reply_to_id: "10",
               req_options: request_options(adapter)
             )

    assert_received {:rpc_send_body, body}
    assert body["params"]["account"] == "+15555550101"
    assert body["params"]["groupId"] == "group-1"
    assert body["params"]["quoteTimestamp"] == "10"
    assert body["params"]["quoteAuthor"] == "group:group-1"
    refute Map.has_key?(body["params"], "attachments")

    assert {:ok, _} =
             JsonRpcClient.send_message(nil, "+15555550100", "reply",
               endpoint: "http://signal.test/api/v1/rpc",
               reply_to_id: "11",
               quote_message: "parent",
               req_options: request_options(adapter)
             )

    assert_received {:rpc_send_body, body}
    assert body["params"]["quoteMessage"] == "parent"
  end

  test "normalizes nil and single receive results with string limits" do
    test_pid = self()

    nil_adapter = fn request ->
      body = Jason.decode!(request.body)
      send(test_pid, {:rpc_receive_body, body, request.options})
      {request, %{Req.Response.json(%{"result" => nil}) | status: 200}}
    end

    assert {:ok, []} =
             JsonRpcClient.receive_messages(nil,
               endpoint: "http://signal.test/api/v1/rpc",
               timeout_s: "2.5",
               max_messages: "7",
               req_options: request_options(nil_adapter)
             )

    assert_received {:rpc_receive_body, body, options}
    assert body["params"] == %{"timeout" => 2.5, "maxMessages" => 7}
    assert options.receive_timeout == 15_000

    one_adapter = fn request ->
      {request, %{Req.Response.json(%{"result" => %{"envelope" => %{}}}) | status: 200}}
    end

    assert {:ok, [%{"envelope" => %{}}]} =
             JsonRpcClient.receive_messages(nil,
               endpoint: "http://signal.test/api/v1/rpc",
               req_options: request_options(one_adapter)
             )
  end

  test "returns unexpected daemon responses and transport errors" do
    unexpected = fn request ->
      {request, %{Req.Response.json(%{"unexpected" => true}) | status: 503}}
    end

    assert {:error, {:signal_rpc_error, 503, %{"unexpected" => true}}} =
             JsonRpcClient.receive_messages(nil,
               endpoint: "http://signal.test/api/v1/rpc",
               req_options: request_options(unexpected)
             )

    failed = fn request ->
      {request, %Req.TransportError{reason: :timeout}}
    end

    assert {:error, %Req.TransportError{reason: :timeout}} =
             JsonRpcClient.receive_messages(nil,
               endpoint: "http://signal.test/api/v1/rpc",
               req_options: request_options(failed)
             )
  end
end
