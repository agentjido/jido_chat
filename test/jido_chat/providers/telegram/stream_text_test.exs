defmodule Jido.Chat.Telegram.StreamTextTest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true
  alias Jido.Chat.{Client, Signal}
  alias Jido.Chat.Telegram.Adapter

  defmodule Transport do
    def call(_token, method, payload, opts) do
      send(opts[:observer], {:wire, method, payload, self()})
      if response = opts[:response], do: response.(method, payload), else: response(method, payload)
    end

    def response(method, payload) when method in ["sendMessage", "sendRichMessage", "editMessageText"] do
      {:ok, %{"message_id" => 42, "chat" => %{"id" => payload["chat_id"]}, "text" => payload["text"] || "rich"}}
    end

    def response(_, _), do: {:ok, true}
  end

  defmodule Flow do
    use Jido.Flow, name: "stream_text_test_flow"

    flow do
      step("deliver", action: Jido.Chat.StreamText, params: input(:signal))
      output(%{signal: result("deliver")})
    end
  end

  defp client(config \\ []),
    do:
      Client.new!(Adapter, id: "telegram", credentials: %{token: "private-token"}, config: config, transport: Transport)

  defp stream(chunks, opts \\ []) do
    Jido.Chat.stream_text(client(), "123", chunks, Keyword.put_new(opts, :options, observer: self()))
  end

  defp calls(acc \\ []) do
    receive do
      {:wire, method, payload, pid} -> calls([{method, payload, pid} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "private chat defaults to draft previews and one final send with a stable draft ID" do
    assert {:ok, completed} = stream(["Hello", " world"], update_interval_ms: 0)
    assert completed.type == Jido.Chat.StreamText.Completed.type()
    assert completed.data["result"]["id"] == "42"

    assert [
             {"sendMessageDraft", first, first_pid},
             {"sendMessageDraft", second, second_pid},
             {"sendMessage", final, final_pid}
           ] = calls()

    for execution_pid <- [first_pid, second_pid, final_pid], do: refute(Process.alive?(execution_pid))
    assert first["chat_id"] == 123
    assert first["draft_id"] == second["draft_id"] and first["draft_id"] > 0
    assert first["text"] == "Hello" and second["text"] == "Hello world"
    assert final["text"] == "Hello world"
    refute Map.has_key?(final, "draft_id")
  end

  test "groups use send and edit, keeping reply and thread routing on the first write" do
    keyboard = %{"rows" => [[%{"text" => "Read", "url" => "https://example.com"}]]}

    assert {:ok, _} =
             Jido.Chat.stream_text(client(), "-100123", ["One", " two"],
               thread_id: "7",
               reply_to_id: "8",
               keyboard: keyboard,
               update_interval_ms: 0,
               options: [observer: self()]
             )

    assert [{"sendMessage", first, _}, {"editMessageText", edit, _}] = calls()
    assert first["message_thread_id"] == "7"
    assert first["reply_parameters"] == %{"message_id" => "8"}
    assert first["reply_markup"] == edit["reply_markup"]
    assert edit["message_id"] == "42" and edit["text"] == "One two"
    refute Map.has_key?(edit, "message_thread_id")
    refute Map.has_key?(edit, "reply_parameters")
  end

  test "the adapter can select edits for a private chat through client configuration" do
    assert {:ok, _} =
             Jido.Chat.stream_text(client(stream_delivery: :edit), "123", ["One", " two"], options: [observer: self()])

    assert [{"sendMessage", _, _}, {"editMessageText", _, _}] = calls()
  end

  test "rich drafts use safe Markdown previews and preserve exact final text" do
    assert {:ok, _} =
             stream(["**Hello", " world**"],
               format: :markdown,
               update_interval_ms: 0,
               reply_to_id: "5",
               thread_id: "7",
               keyboard: %{"rows" => [[%{"text" => "OK", "value" => "ok"}]]}
             )

    assert [{"sendRichMessageDraft", first, _}, {"sendRichMessageDraft", second, _}, {"sendRichMessage", final, _}] =
             calls()

    assert first["rich_message"] == %{"markdown" => "**Hello**"}
    assert second["rich_message"] == %{"markdown" => "**Hello world**"}
    assert final["rich_message"] == %{"markdown" => "**Hello world**"}
    assert final["reply_parameters"] == %{"message_id" => "5"}
    assert final["message_thread_id"] == "7"
    assert final["reply_markup"]
    refute Map.has_key?(first, "reply_markup")
  end

  test "MDEx link previews keep the partial URL private and final source exact" do
    assert {:ok, _} =
             stream(["Read [guide](https://ji", "do.run)", "\n\n"],
               format: :markdown,
               update_interval_ms: 0
             )

    assert [{"sendRichMessageDraft", first, _}, {"sendRichMessageDraft", second, _}, {"sendRichMessage", final, _}] =
             calls()

    assert first["rich_message"] == %{"markdown" => "Read [guide](mdex:incomplete-link)"}
    assert second["rich_message"] == %{"markdown" => "Read [guide](https://jido.run)"}
    assert final["rich_message"] == %{"markdown" => "Read [guide](https://jido.run)\n\n"}
  end

  test "plain and HTML text do not get Markdown repairs" do
    for format <- [:plain, :html] do
      assert {:ok, _} = stream(["*literal"], format: format)
      assert [{_, preview, _}, {_, final, _}] = calls()

      if format == :plain do
        assert preview["text"] == "*literal" and final["text"] == "*literal"
      else
        assert preview["rich_message"] == %{"html" => "*literal"}
        assert final["rich_message"] == %{"html" => "*literal"}
      end
    end
  end

  test "throttling coalesces fast chunks and always flushes the final content" do
    assert {:ok, _} =
             Jido.Chat.stream_text(client(), "-123", ["one", " two", " three"],
               update_interval_ms: 60_000,
               options: [observer: self()]
             )

    assert [{"sendMessage", first, _}, {"editMessageText", final, _}] = calls()
    assert first["text"] == "one" and final["text"] == "one two three"
  end

  test "throttled Markdown chunks keep their original syntax until final delivery" do
    assert {:ok, _} =
             Jido.Chat.stream_text(client(), "-123", ["**one", " two", " three**"],
               format: :markdown,
               update_interval_ms: 60_000,
               options: [observer: self()]
             )

    assert [{"sendRichMessage", first, _}, {"editMessageText", final, _}] = calls()
    assert first["rich_message"] == %{"markdown" => "**one**"}
    assert final["rich_message"] == %{"markdown" => "**one two three**"}
  end

  test "an unchanged final snapshot does not cause a duplicate edit" do
    assert {:ok, _} = Jido.Chat.stream_text(client(), "@channel", ["once", ""], options: [observer: self()])
    assert [{"sendMessage", %{"text" => "once"}, _}] = calls()
  end

  test "empty and whitespace sources fail without provider writes" do
    for source <- [[], ["", "  ", "\n"]] do
      assert {:error, %Jido.Chat.Error{signal: failed}} = stream(source)
      assert failed.data["outcome"] == "not_attempted"
    end

    assert calls() == []
  end

  test "invalid delivery configuration fails before pulling the source" do
    caller = self()

    source =
      Stream.map(["one"], fn text ->
        send(caller, :pulled)
        text
      end)

    for {mode, room} <- [{:wrong, "123"}, {:draft, "-123"}] do
      assert {:error, %Jido.Chat.Error{signal: failed}} =
               Jido.Chat.stream_text(client(stream_delivery: mode), room, source)

      assert failed.data["outcome"] == "not_attempted"
    end

    refute_receive :pulled
    assert calls() == []
  end

  test "a failed draft stops enumeration and does not persist a final message" do
    caller = self()

    source =
      Stream.map(["one", "two"], fn text ->
        send(caller, {:pulled, text})
        text
      end)

    response = fn _, _ -> {:error, {:rejected, :private_failure}} end
    assert {:error, %Jido.Chat.Error{signal: failed}} = stream(source, options: [observer: self(), response: response])
    assert failed.data["outcome"] == "unknown"
    assert_receive {:pulled, "one"}
    refute_receive {:pulled, "two"}
    assert [{"sendMessageDraft", _, _}] = calls()
    refute inspect(failed) =~ "private_failure"
  end

  test "a failed edit stops the source without replaying the initial send" do
    caller = self()

    source =
      Stream.map(["one", " two", " three"], fn text ->
        send(caller, {:pulled, text})
        text
      end)

    response = fn
      "editMessageText", _ -> {:error, :timeout}
      method, payload -> Transport.response(method, payload)
    end

    assert {:error, %Jido.Chat.Error{}} =
             Jido.Chat.stream_text(client(), "-123", source,
               update_interval_ms: 0,
               options: [observer: self(), response: response]
             )

    refute_receive {:pulled, " three"}
    assert [{"sendMessage", _, _}, {"editMessageText", _, _}] = calls()
  end

  test "source exceptions return a safe failure Signal and do not send a final message" do
    source =
      Stream.map(["one", "two"], fn
        "one" -> "one"
        _ -> raise "private source error"
      end)

    assert {:error, %Jido.Chat.Error{signal: failed}} = stream(source)
    assert failed.type == Jido.Chat.StreamText.Failed.type()
    refute inspect(failed) =~ "private source error"
    assert [{"sendMessageDraft", _, _}] = calls()
  end

  test "native Flow runs the same StreamText Action with the source in private context" do
    request = Signal.StreamText.new!(%{"client_id" => "telegram", "request_id" => "r", "room_id" => "123"})

    assert {:ok, %{signal: data}} =
             Jido.Exec.run(
               Flow,
               %{signal: request.data},
               %{client: client(), signal: request, options: [stream: ["flow"], observer: self()]},
               max_attempts: 1
             )

    assert {:ok, completed} = Jido.Chat.StreamText.reply(request, data, source: client().source)

    assert completed.extensions["jidocausationid"] == request.id
    assert {:ok, json} = Jido.Signal.Codec.serialize(completed)
    assert {:ok, ^completed} = Jido.Signal.Catalog.decode(Jido.Chat.Telegram.catalog(), json)
    refute json =~ "private-token"
    assert [{"sendMessageDraft", _, _}, {"sendMessage", _, _}] = calls()
  end

  test "a failure during final persistence returns a failure rather than a draft acknowledgement" do
    response = fn
      "sendMessage", _ -> {:error, :timeout}
      method, payload -> Transport.response(method, payload)
    end

    assert {:error, %Jido.Chat.Error{signal: failed}} = stream(["one"], options: [observer: self(), response: response])
    assert failed.type == Jido.Chat.StreamText.Failed.type()
    assert failed.data["outcome"] == "unknown"
    assert [{"sendMessageDraft", _, _}, {"sendMessage", _, _}] = calls()
  end

  test "a failed final flush stops without another edit attempt" do
    response = fn
      "editMessageText", _ -> {:error, :timeout}
      method, payload -> Transport.response(method, payload)
    end

    assert {:error, %Jido.Chat.Error{}} =
             Jido.Chat.stream_text(client(), "-123", ["one", " two"],
               update_interval_ms: 60_000,
               options: [observer: self(), response: response]
             )

    assert [{"sendMessage", _, _}, {"editMessageText", %{"text" => "one two"}, _}] = calls()
  end

  test "a halted stream closes its resource after the first failed write" do
    caller = self()

    source =
      Stream.resource(
        fn -> 0 end,
        fn n -> {[Integer.to_string(n)], n + 1} end,
        fn _ -> send(caller, :source_closed) end
      )

    response = fn _, _ -> {:error, :timeout} end
    assert {:error, %Jido.Chat.Error{}} = stream(source, options: [observer: self(), response: response])
    assert_receive :source_closed
    assert [{"sendMessageDraft", _, _}] = calls()
  end

  test "structured text chunks use the same delivery path" do
    assert {:ok, _} = stream([Jido.Chat.StreamChunk.text("one"), %{kind: :text, text: " two"}])
    assert [{"sendMessageDraft", _, _}, {"sendMessage", %{"text" => "one two"}, _}] = calls()
  end

  test "a pending Markdown snapshot is written when the next chunk has no visible text" do
    chunks =
      Stream.map(["one", " two", ""], fn text ->
        if text == "", do: Process.sleep(110)
        text
      end)

    assert {:ok, _} = stream(chunks, format: :markdown, update_interval_ms: 100)

    assert [{"sendRichMessageDraft", first, _}, {"sendRichMessageDraft", second, _}, {"sendRichMessage", final, _}] =
             calls()

    assert first["rich_message"] == %{"markdown" => "one"}
    assert second["rich_message"] == %{"markdown" => "one two"}
    assert final["rich_message"] == %{"markdown" => "one two"}
  end
end
