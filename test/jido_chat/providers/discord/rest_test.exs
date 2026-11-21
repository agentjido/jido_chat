defmodule Jido.Chat.Discord.RESTTest do
  use ExUnit.Case, async: true
  alias Jido.Chat.Discord.Transport.REST

  test "request uses an explicit token and disables retries and redirects" do
    adapter = fn request ->
      assert Req.Request.get_header(request, "authorization") == ["Bot token"]
      assert request.options.retry == false
      assert request.options.redirect == false
      assert to_string(request.url) == "https://discord.com/api/v10/channels/1/messages"
      assert Jason.decode!(request.body) == %{"content" => "hello"}
      {request, Req.Response.new(status: 200, body: %{"id" => "1"})}
    end

    assert {:ok, %{"id" => "1"}} =
             REST.call("token", :post, "/channels/1/messages", %{"content" => "hello"},
               adapter: Jido.Chat.Discord.TestHTTP,
               finch_private: [discord_test_handler: adapter]
             )
  end

  test "multipart carries bytes and payload in the same request" do
    adapter = fn request ->
      body = request.body |> Enum.to_list() |> IO.iodata_to_binary()
      assert body =~ "payload_json"
      assert body =~ "test.txt"
      assert body =~ "bytes"
      {request, Req.Response.new(status: 200, body: %{})}
    end

    assert {:ok, %{}} =
             REST.call("token", :post, "/channels/1/messages", {:multipart, %{}, "bytes", "test.txt"},
               adapter: Jido.Chat.Discord.TestHTTP,
               finch_private: [discord_test_handler: adapter]
             )
  end

  test "HTTP failures are classified without token or response body leaks" do
    for {status, category} <- [
          {400, :provider_failure},
          {401, :unauthorized},
          {403, :forbidden},
          {404, :not_found},
          {429, :rate_limited}
        ] do
      adapter = fn req ->
        {req, Req.Response.new(status: status, body: %{"secret" => "token", "retry_after" => 1.5})}
      end

      assert {:error, {:rejected, ^category, %{retry_after_ms: 1500}}} =
               REST.call("token", :get, "/test", nil,
                 adapter: Jido.Chat.Discord.TestHTTP,
                 finch_private: [discord_test_handler: adapter]
               )
    end

    adapter = fn req -> {req, Req.Response.new(status: 503, body: "secret")} end

    assert {:error, :provider_failure} =
             REST.call("token", :get, "/test", nil,
               adapter: Jido.Chat.Discord.TestHTTP,
               finch_private: [discord_test_handler: adapter]
             )

    adapter = fn req -> {req, %Req.TransportError{reason: :timeout}} end

    assert {:error, :transport_failure} =
             REST.call("token", :get, "/test", nil,
               adapter: Jido.Chat.Discord.TestHTTP,
               finch_private: [discord_test_handler: adapter]
             )

    adapter = fn req -> {req, Req.Response.new(status: 400, body: %{})} end

    assert {:error, {:rejected, :provider_failure, %{}}} =
             REST.call("token", :get, "/test", nil,
               adapter: Jido.Chat.Discord.TestHTTP,
               finch_private: [discord_test_handler: adapter]
             )
  end
end
