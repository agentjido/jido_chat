defmodule Jido.Chat.Slack.SocketMode.ReqClientTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Slack.SocketMode.ReqClient

  defmodule MockReq do
    def request(opts) do
      send(self(), {:req_request, opts})

      {:ok,
       %Req.Response{
         status: 200,
         body: %{"ok" => true, "url" => "wss://slack.example/socket"}
       }}
    end
  end

  defmodule ErrorReq do
    def request(_opts) do
      {:ok,
       %Req.Response{
         status: 200,
         body: %{"ok" => false, "error" => "not_authed"}
       }}
    end
  end

  defmodule FixtureReq do
    def request(opts) do
      send(self(), {:req_request, opts})
      receive do: ({:reply, result} -> result)
    end
  end

  test "open_socket/2 calls apps.connections.open with the app token" do
    assert {:ok, "wss://slack.example/socket"} =
             ReqClient.open_socket("xapp-test", req: MockReq)

    assert_received {:req_request, opts}
    assert opts[:url] == "https://slack.com/api/apps.connections.open"
    assert {"authorization", "Bearer xapp-test"} in opts[:headers]
  end

  test "open_socket/2 surfaces Slack API errors explicitly" do
    assert {:error, {:slack_api_error, "not_authed", _body}} =
             ReqClient.open_socket("xapp-test", req: ErrorReq)
  end

  test "open_socket/2 uses runtime base_url" do
    assert {:ok, "wss://slack.example/socket"} =
             ReqClient.open_socket("xapp-test",
               req: MockReq,
               base_url: "https://slack-proxy.test/api"
             )

    assert_received {:req_request, opts}
    assert opts[:url] == "https://slack-proxy.test/api/apps.connections.open"
  end

  test "open_socket/2 distinguishes HTTP, transport, and malformed connection responses" do
    for {reply, expected} <- [
          {{:ok, Req.Response.new(status: 503, body: "offline")}, {:http_error, 503, "offline"}},
          {{:ok, Req.Response.new(status: 200, body: %{"ok" => true})}, {:missing_socket_url, %{"ok" => true}}},
          {{:ok, Req.Response.new(status: 200, body: "bad body")}, {:invalid_response, "bad body"}},
          {{:error, :timeout}, :timeout}
        ] do
      send(self(), {:reply, reply})
      assert {:error, ^expected} = ReqClient.open_socket("xapp-test", req: FixtureReq, headers: [{"x-test", "fixture"}])
      assert_received {:req_request, request}
      assert {"x-test", "fixture"} in request[:headers]
    end

    assert {:ok, _} = ReqClient.open_socket("xapp-test", req: MockReq, headers: %{"x-test" => "fixture"})
    assert_received {:req_request, request}
    assert {"x-test", "fixture"} in request[:headers]
  end
end
