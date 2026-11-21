defmodule Jido.Chat.Telegram.ExGramAdapterTest do
  use ExUnit.Case, async: true
  alias Jido.Chat.Telegram.{ExGramAdapter, TestHTTP}

  test "GET is sent as POST with JSON and string-key HTTP options" do
    {result, wire} =
      TestHTTP.serve(200, ~s({"ok":true,"result":{"id":7}}), fn url ->
        ExGramAdapter.request(:get, "/botfixture/getMe", %{chat_id: 42}, %{
          "url" => url,
          "base_url" => "http://unused.invalid",
          "connect_timeout" => 1_000,
          "connect_options" => [timeout: 1_000],
          "pool_timeout" => 1_000,
          "receive_timeout" => 1_000,
          "unknown" => :ignored
        })
      end)

    assert result == {:ok, %{id: 7}}
    assert wire =~ "POST /botfixture/getMe HTTP/1.1"
    assert String.downcase(wire) =~ "content-type: application/json"
    [_, body] = String.split(wire, "\r\n\r\n", parts: 2)
    assert Jason.decode!(body) == %{"chat_id" => 42}
  end

  test "a supplied Finch pool works without an implicit connect_options conflict" do
    {result, _} =
      TestHTTP.serve(200, ~s({"ok":true,"result":true}), fn url ->
        ExGramAdapter.request(:post, "/request", %{}, [{"url", url}, {"finch", [name: Req.Finch]}])
      end)

    assert result == {:ok, true}
  end

  test "multipart uploads preserve bytes, filenames, and ordinary fields" do
    path = Path.join(System.tmp_dir!(), "telegram-upload-#{System.unique_integer([:positive])}.txt")
    File.write!(path, "disk upload bytes")
    on_exit(fn -> File.rm(path) end)

    {result, wire} =
      TestHTTP.serve(200, ~s({"ok":true,"result":true}), fn url ->
        ExGramAdapter.request(
          :post,
          "/upload",
          {:multipart,
           [
             {:file, "document", path},
             {:file_content, "photo", "inline bytes", "photo.txt"},
             {"chat_id", "42"}
           ]},
          [nil, {"unknown", 1}, {:base_url, url}]
        )
      end)

    assert result == {:ok, true}
    assert wire =~ "multipart/form-data"
    assert wire =~ "disk upload bytes"
    assert wire =~ "inline bytes"
    assert wire =~ "photo.txt"
    assert wire =~ "name=\"chat_id\""
    assert wire =~ "42"
  end

  test "HTTP errors and Telegram rejection envelopes stay errors" do
    for {status, body} <- [{400, ~s({"ok":false,"description":"bad request"})}, {200, ~s({"ok":false})}] do
      {result, _} =
        TestHTTP.serve(status, body, fn url ->
          ExGramAdapter.request(:post, "/request", %{}, base_url: url)
        end)

      assert {:error, %ExGram.Error{code: :response_status_not_match, message: message}} = result
      assert Jason.decode!(message)["ok"] == false
    end
  end

  test "invalid JSON returns the decoder error" do
    {result, _} =
      TestHTTP.serve(200, "invalid JSON", fn url ->
        ExGramAdapter.request(:post, "/request", %{}, url: url)
      end)

    assert {:error, %ExGram.Error{code: %Jason.DecodeError{}}} = result
  end

  test "connection failure returns an ExGram error" do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)

    assert {:error, %ExGram.Error{code: %Req.TransportError{reason: :econnrefused}}} =
             ExGramAdapter.request(:post, "/request", %{}, url: "http://127.0.0.1:#{port}")
  end
end
