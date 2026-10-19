defmodule Jido.Chat.TextAPITest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true
  alias Jido.Chat.{Client, Signal}

  defmodule Adapter do
    use Jido.Chat.Adapter
    def capabilities, do: %{send_message: :native, send_file: :native, stream_text: :native}
    def normalize(_, _, _), do: {:error, :unused}

    def invoke(_client, request, opts) do
      send(opts[:observer], {:request, request, Keyword.delete(opts, :stream), self()})

      text =
        if request.type == Signal.StreamText.type() do
          Enum.map_join(opts[:stream], fn chunk ->
            send(opts[:observer], {:chunk, chunk, self()})
            chunk
          end)
        else
          request.data["text"] || request.data["caption"] || "file"
        end

      {:ok, %{"id" => "m", "room_id" => request.data["room_id"], "text" => text, "status" => "sent"}}
    end
  end

  defmodule Unsupported do
    use Jido.Chat.Adapter
    def capabilities, do: %{}
    def normalize(_, _, _), do: {:error, :unused}
    def invoke(_, _, _), do: raise("must not call provider")
  end

  defp client, do: Client.new!(Adapter, id: "test", credentials: %{token: "private-token"})

  test "send_text builds the exact SendMessage command and preserves request and trace context" do
    trace = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
    keyboard = %{"rows" => [[%{"text" => "Read", "url" => "https://example.com"}]]}

    assert {:ok, completed} =
             Jido.Chat.send_text(client(), "room", "**Ready**",
               request_id: "explicit",
               format: :markdown,
               thread_id: "thread",
               reply_to_id: "reply",
               keyboard: keyboard,
               signal_options: [extensions: %{"traceparent" => trace}],
               options: [observer: self()]
             )

    assert_receive {:request, request, [observer: observer], pid}
    assert observer == self()
    refute Process.alive?(pid)
    assert request.type == Signal.SendMessage.type()
    assert request.source == client().source

    assert request.data == %{
             "client_id" => "test",
             "request_id" => "explicit",
             "room_id" => "room",
             "text" => "**Ready**",
             "format" => "markdown",
             "thread_id" => "thread",
             "reply_to_id" => "reply",
             "keyboard" => keyboard
           }

    assert completed.type == Jido.Chat.SendMessage.Completed.type()
    assert completed.extensions["traceparent"] == trace
    assert completed.extensions["causationid"] == request.id
    assert {:ok, json} = Jido.Signal.Serialization.serialize(completed)
    refute json =~ "private-token"
  end

  test "request IDs are generated for each call and explicit string formats work" do
    for _ <- 1..2 do
      assert {:ok, _} = Jido.Chat.send_text(client(), "room", "Hello", format: "plain", options: [observer: self()])
    end

    assert_receive {:request, first, _, _}
    assert_receive {:request, second, _, _}
    assert Jido.Signal.ID.valid?(first.data["request_id"])
    assert first.data["request_id"] != second.data["request_id"]
  end

  test "send_file uses the existing source schema and SendFile Action" do
    source = %{"content_base64" => Base.encode64("report"), "filename" => "report.txt"}

    assert {:ok, completed} =
             Jido.Chat.send_file(client(), "room", source,
               caption: "Report",
               media_kind: :file,
               format: :plain,
               options: [observer: self()]
             )

    assert completed.type == Jido.Chat.SendFile.Completed.type()
    assert_receive {:request, request, _, _}
    assert request.data["source"] == source
    assert request.data["media_kind"] == "file"
    assert request.data["caption"] == "Report"
  end

  test "one Action execution consumes the lazy source and receives only serializable command metadata" do
    caller = self()

    source =
      Stream.map(["one", " two"], fn chunk ->
        send(caller, {:pulled, chunk, self()})
        chunk
      end)

    assert {:ok, completed} =
             Jido.Chat.stream_text(client(), "room", source, update_interval_ms: 50, options: [observer: self()])

    assert completed.type == Jido.Chat.StreamText.Completed.type()
    assert completed.data["result"]["text"] == "one two"
    assert_receive {:request, request, [observer: ^caller], execution_pid}
    refute Process.alive?(execution_pid)
    assert request.data["update_interval_ms"] == 50
    refute Map.has_key?(request.data, "stream")
    assert {:ok, json} = Jido.Signal.Serialization.serialize(request)
    assert {:ok, ^request} = Jido.Signal.Catalog.decode(Jido.Chat.catalog(), json)
    assert_receive {:pulled, "one", ^execution_pid}
    assert_receive {:pulled, " two", ^execution_pid}
    assert_receive {:chunk, "one", ^execution_pid}
    assert_receive {:chunk, " two", ^execution_pid}
  end

  test "StreamText is a native Action and reports missing or invalid local sources before adapter I/O" do
    request = Signal.StreamText.new!(%{"client_id" => "test", "request_id" => "r", "room_id" => "room"})

    for options <- [[observer: self()], [observer: self(), stream: 42]] do
      assert {:error, %Jido.Chat.Error{signal: failed}} =
               Jido.Exec.run(Jido.Chat.StreamText, %{signal: request}, %{client: client(), options: options},
                 max_attempts: 1
               )

      assert failed.type == Jido.Chat.StreamText.Failed.type()
      assert failed.data["outcome"] == "not_attempted"
    end

    refute_receive {:request, _, _, _}
  end

  test "unsupported streaming does not pull the source" do
    client = Client.new!(Unsupported, id: "unsupported")
    caller = self()

    source =
      Stream.map(["text"], fn text ->
        send(caller, :pulled)
        text
      end)

    assert {:error, %Jido.Chat.Error{code: :unsupported}} = Jido.Chat.stream_text(client, "room", source)
    refute_receive :pulled
  end

  test "invalid input, duplicate options, and misspelled options fail before provider I/O" do
    for options <- [
          [unknown: true],
          [format: :plain, format: :html],
          [options: :bad],
          [options: [stream: ["hidden"]]],
          [signal_options: [unknown: true]],
          [format: :unknown],
          [request_id: ""],
          [:bad]
        ] do
      assert {:error, _} = Jido.Chat.send_text(client(), "room", "text", options)
    end

    assert {:error, _} = Jido.Chat.send_text(nil, "room", "text")
    assert {:error, _} = Jido.Chat.send_text(client(), "room", "text", :bad)
    assert {:error, _} = Jido.Chat.send_text(client(), "", "text")
    assert {:error, _} = Jido.Chat.send_file(client(), "room", %{"content_base64" => "invalid", "filename" => "file"})
    assert {:error, _} = Jido.Chat.stream_text(client(), "room", "not an Enumerable")
    assert {:error, _} = Jido.Chat.stream_text(client(), "room", [], update_interval_ms: -1)
    refute_receive {:request, _, _, _}
  end
end
