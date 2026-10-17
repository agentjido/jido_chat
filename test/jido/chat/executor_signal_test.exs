defmodule Jido.Chat.ExecutorSignalTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Errors.Contract
  alias Jido.Signal.{Catalog, Serialization, Trace}

  @operations Path.expand("../../../docs/migration/operations.json", __DIR__)
              |> File.read!()
              |> Jason.decode!()
              |> Map.fetch!("operations")
  @results Map.new(@operations, fn row -> {String.to_atom(row["operation"]), row["result_fixture"]} end)

  defmodule Native do
    @callbacks [
      send_message: 3,
      send_file: 3,
      post_message: 3,
      edit_message: 4,
      delete_message: 3,
      start_typing: 2,
      fetch_metadata: 2,
      fetch_thread: 2,
      fetch_message: 3,
      get_user: 2,
      fetch_subject: 2,
      get_thread_participants: 2,
      mark_as_read: 3,
      fetch_media: 2,
      add_reaction: 4,
      remove_reaction: 4,
      post_ephemeral: 4,
      post_channel_message: 3,
      stream: 3,
      open_modal: 3,
      load_options: 2,
      fetch_messages: 2,
      fetch_channel_messages: 2,
      list_threads: 2,
      open_thread: 3,
      open_dm: 2
    ]

    def signal_protocol, do: 1
    def configure_binding(opts), do: {:ok, opts}
    def normalize_event(_binding, _request), do: {:error, :invalid_delivery}
    def capabilities, do: Map.new(@callbacks, fn {name, _} -> {name, :native} end)

    for {operation, arity} <- @callbacks do
      args = Macro.generate_arguments(arity, __MODULE__)

      def unquote(operation)(unquote_splicing(args)) do
        call(unquote(operation), [unquote_splicing(args)])
      end
    end

    defp call(operation, arguments) do
      opts = List.last(arguments)
      send(opts[:notify], {:callback, operation, arguments})

      case opts[:mode] do
        :error ->
          {:error, {:private_provider_failure, "private-token"}}

        :raise ->
          raise "private provider exception"

        :invalid ->
          {:ok, self()}

        _ ->
          if operation == :fetch_media,
            do: {:ok, <<255, 1, 2>>},
            else: {:ok, opts[:results][operation]}
      end
    end
  end

  defmodule Unsupported do
    def signal_protocol, do: 1
    def configure_binding(opts), do: {:ok, opts}
    def normalize_event(_binding, _request), do: {:error, :invalid_delivery}

    def capabilities,
      do:
        Map.new(Jido.Chat.Operations.Definitions.all(), fn {_type, {_module, operation, _fields, _shape, _schema}} ->
          {operation, :unsupported}
        end)
  end

  defmodule Fallback do
    def signal_protocol, do: 1
    def configure_binding(opts), do: {:ok, opts}
    def normalize_event(_binding, _request), do: {:error, :invalid_delivery}

    def capabilities,
      do: %{
        send_message: :native,
        send_file: :native,
        edit_message: :native,
        open_dm: :native,
        fetch_thread: :native,
        post_message: :fallback,
        post_channel_message: :fallback,
        fetch_metadata: :fallback,
        fetch_subject: :fallback,
        post_ephemeral: :fallback,
        stream: :fallback
      }

    defdelegate send_message(room, text, opts), to: Native
    defdelegate send_file(room, file, opts), to: Native
    defdelegate edit_message(room, message, text, opts), to: Native
    defdelegate open_dm(user, opts), to: Native
    defdelegate fetch_thread(room, opts), to: Native
  end

  defmodule Blocking do
    def signal_protocol, do: 1
    def configure_binding(opts), do: {:ok, opts}
    def normalize_event(_binding, _request), do: {:error, :invalid_delivery}
    def capabilities, do: %{send_message: :native}

    def send_message(room, text, opts) do
      send(opts[:notify], {:provider_started, self()})

      receive do
        :release -> {:ok, %{"id" => "message-1", "room_id" => room, "text" => text}}
      end
    end
  end

  defmodule OptionsDeadline do
    def signal_protocol, do: 1
    def configure_binding(opts), do: {:ok, opts}
    def normalize_event(_binding, _request), do: {:error, :invalid_delivery}
    def capabilities, do: %{load_options: :native}

    def load_options(_request, opts) do
      send(opts[:notify], {:options_started, self()})

      if opts[:mode] == :kill do
        Process.exit(self(), :kill)
      else
        receive do
          :complete -> {:ok, %{options: [%{label: "Ada", value: "ada"}]}}
        end
      end
    end
  end

  test "options callback stops when its caller dies without repeating the accepted request" do
    {:ok, binding} =
      Jido.Chat.bind(OptionsDeadline, id: "options", notify: self(), timeout_ms: 5_000)

    request =
      Jido.Chat.Signal.LoadOptions.new!(%{
        "request_id" => "owner-death",
        "interaction_id" => "one",
        "query" => "a"
      })

    caller = spawn(fn -> Jido.Chat.execute(binding, request) end)
    caller_monitor = Process.monitor(caller)
    assert_receive {:options_started, worker}
    worker_monitor = Process.monitor(worker)
    on_exit(fn -> if Process.alive?(worker), do: Process.exit(worker, :kill) end)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^caller_monitor, :process, ^caller, :killed}
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, :killed}, 500

    assert {:error, %Contract{code: :request_outcome_unknown}} =
             Jido.Chat.execute(binding, request)

    refute_received {:options_started, _}
  end

  test "options callback process failure does not stop its caller" do
    {:ok, binding} = Jido.Chat.bind(OptionsDeadline, id: "options", notify: self(), mode: :kill)

    request =
      Jido.Chat.Signal.LoadOptions.new!(%{
        "request_id" => "worker-death",
        "interaction_id" => "one",
        "query" => "a"
      })

    assert {:ok, result} = Jido.Chat.execute(binding, request)
    assert result.type == Jido.Chat.Signal.OperationFailed.type()
    assert result.data["code"] == "provider_failure"
    assert {:ok, ^result} = Jido.Chat.execute(binding, request)
    assert_received {:options_started, _}
    refute_received {:options_started, _}
  end

  test "options deadline stops the worker while its caller is suspended" do
    {:ok, binding} =
      Jido.Chat.bind(OptionsDeadline, id: "options", notify: self(), timeout_ms: 100)

    observer = self()

    request =
      Jido.Chat.Signal.LoadOptions.new!(%{
        "request_id" => "suspended-owner",
        "interaction_id" => "one",
        "query" => "a"
      })

    caller =
      spawn(fn -> send(observer, {:options_result, Jido.Chat.execute(binding, request)}) end)

    assert_receive {:options_started, worker}
    worker_monitor = Process.monitor(worker)
    on_exit(fn -> if Process.alive?(worker), do: Process.exit(worker, :kill) end)
    :erlang.suspend_process(caller)

    try do
      assert_receive {:DOWN, ^worker_monitor, :process, ^worker, :killed}, 500
      assert Process.alive?(caller)
    after
      :erlang.resume_process(caller)
    end

    assert_receive {:options_result, {:ok, result}}
    assert result.data["code"] == "provider_failure"
    assert {:ok, ^result} = Jido.Chat.execute(binding, request)
    refute_received {:options_started, _}
  end

  test "options callback is stopped at the captured deadline and the result is not rerun" do
    {:ok, binding} =
      Jido.Chat.bind(OptionsDeadline, id: "options", notify: self(), timeout_ms: 20)

    request =
      Jido.Chat.Signal.LoadOptions.new!(%{
        "request_id" => "deadline",
        "interaction_id" => "one",
        "query" => "a"
      })

    assert {:ok, result} = Jido.Chat.execute(binding, request)
    assert result.type == Jido.Chat.Signal.OperationFailed.type()
    assert result.data["code"] == "provider_failure"
    assert_received {:options_started, worker}
    refute Process.alive?(worker)
    assert {:ok, ^result} = Jido.Chat.execute(binding, request)
    refute_received {:options_started, _}
  end

  test "invalid options deadline is rejected before the provider callback" do
    {:ok, binding} = Jido.Chat.bind(OptionsDeadline, id: "options", notify: self(), timeout_ms: 0)

    request =
      Jido.Chat.Signal.LoadOptions.new!(%{"request_id" => "deadline", "interaction_id" => "one", "query" => "a"})

    assert {:error, %Contract{code: :invalid_request}} = Jido.Chat.execute(binding, request)
    refute_received {:options_started, _}
  end

  for row <- @operations do
    operation = String.to_atom(row["operation"])

    test "#{row["operation"]}: one native callback and a registered typed result" do
      row = unquote(Macro.escape(row))
      operation = unquote(operation)
      binding = test_binding(Native)
      request = request(binding, row)
      before = Jido.Signal.to_map(request)
      assert {:ok, result} = Jido.Chat.execute(binding, request)
      assert result.type == Jido.Chat.Signal.OperationCompleted.type()
      assert result.data["operation"] == row["operation"]
      assert result.data["request_id"] == "request-1"
      assert_received {:callback, ^operation, args}
      assert length(args) == row["callback"]["arity"]
      refute_received {:callback, _, _}
      assert Jido.Signal.to_map(request) == before
      assert Jido.Signal.get_context(result, "causationid") == request.id
      assert Trace.get(result).trace_id == Trace.get(request).trace_id
      assert Trace.get(result).span_id != Trace.get(request).span_id
      assert {:ok, encoded} = Serialization.serialize(result)
      assert {:ok, ^result} = Catalog.decode(Catalog.new!(Jido.Chat.signal_definitions()), encoded)

      if row["operation"] == "fetch_media" do
        assert {:ok, <<255, 1, 2>>} = Jido.Chat.resolve_resource(binding, result.data["result"]["resource_ref"])
      end
    end

    test "#{row["operation"]}: private invocation keeps completion in its resource owner" do
      alias Jido.Chat.Operations.Executor
      row = unquote(Macro.escape(row))
      operation = unquote(operation)
      binding = test_binding(Native)
      request = request(binding, row)
      assert {:ok, {:prepared, completion, invocation}} = Executor.prepare(binding, request)
      refute_received {:callback, _, _}
      assert {:error, %Contract{code: :request_in_progress}} = Jido.Chat.execute(binding, request)
      outcome = Task.async(fn -> Executor.invoke(invocation) end) |> Task.await()
      assert_received {:callback, ^operation, _}

      assert {:error, %Contract{code: :request_outcome_unknown}} =
               Task.async(fn -> Executor.complete(completion, outcome) end) |> Task.await()

      assert {:ok, result} = Executor.complete(completion, outcome)
      assert result.type == Jido.Chat.Signal.OperationCompleted.type()
      before = :ets.tab2list(binding.resources) |> Enum.sort()
      assert {:ok, ^result} = Executor.complete(completion, {:error, :late})
      assert before == :ets.tab2list(binding.resources) |> Enum.sort()
      assert {:ok, ^result} = Jido.Chat.execute(binding, request)
      refute_received {:callback, _, _}

      if row["operation"] == "fetch_media" do
        assert {:ok, <<255, 1, 2>>} = Jido.Chat.resolve_resource(binding, result.data["result"]["resource_ref"])
      end
    end

    test "#{row["operation"]}: unsupported selection calls no provider" do
      row = unquote(Macro.escape(row))
      binding = test_binding(Unsupported)
      assert {:ok, result} = Jido.Chat.execute(binding, request(binding, row))
      assert result.type == Jido.Chat.Signal.OperationFailed.type()
      assert result.data["code"] == "unsupported"
      refute_received {:callback, _, _}
    end

    test "#{row["operation"]}: provider failure is a registered result with one callback" do
      row = unquote(Macro.escape(row))
      operation = unquote(operation)
      binding = test_binding(Native, mode: :error)
      assert {:ok, result} = Jido.Chat.execute(binding, request(binding, row))
      assert result.type == Jido.Chat.Signal.OperationFailed.type()
      assert result.data["code"] == "provider_failure"
      assert_received {:callback, ^operation, _}
      refute_received {:callback, _, _}
      refute inspect(result.data) =~ "private-token"
    end
  end

  test "result construction failure preserves the admitted outcome and cannot repeat a provider call" do
    binding = test_binding(Native)
    data = %{"request_id" => "r", "room_id" => "room/1", "text" => "hello"}
    opts = [id: "result-size", time: "2026-10-12T12:00:00Z"]
    base = Jido.Chat.Signal.SendMessage.new!(data, opts)
    {:ok, encoded} = Serialization.serialize(base)
    data = Map.put(data, "request_id", String.duplicate("r", 262_144 - byte_size(encoded) + 1))
    request = Jido.Chat.Signal.SendMessage.new!(data, opts)
    assert {:error, %Contract{} = error} = Jido.Chat.execute(binding, request)
    assert_received {:callback, :send_message, _}
    refute_received {:callback, _, _}
    assert {:error, ^error} = Jido.Chat.execute(binding, request)
    refute_received {:callback, _, _}
  end

  test "unrepresentable parent IDs and conversation keys fail before a provider call" do
    binding = test_binding(Native)
    data = %{"request_id" => "invalid-context", "room_id" => "room/1", "text" => "hello"}
    long_id = Jido.Chat.Signal.SendMessage.new!(data, id: String.duplicate("i", 129))
    assert {:error, %Contract{code: :invalid_request}} = Jido.Chat.execute(binding, long_id)
    long_room = Jido.Chat.Signal.SendMessage.new!(Map.put(data, "room_id", String.duplicate("r", 2_049)))
    assert {:error, %Contract{code: :invalid_context}} = Jido.Chat.execute(binding, long_room)
    refute_received {:callback, _, _}
  end

  test "invalid input, unknown type/schema, and a fact cause zero callbacks" do
    binding = test_binding(Native)
    good = request(binding, operation("send_message"))

    for invalid <- [
          nil,
          %{good | type: "unknown.command"},
          %{good | dataschema: "urn:unknown:1"},
          %{good | data: %{"raw" => true}}
        ] do
      assert {:error, %Contract{}} = Jido.Chat.execute(binding, invalid)
    end

    fact =
      Jido.Chat.Signal.MessageReceived.new!(%{
        "item_id" => "item-1",
        "delivery_id" => "delivery-1",
        "room_id" => "room/1",
        "message_id" => "message-1",
        "sender" => %{"id" => "actor-1"},
        "text" => "hello"
      })

    assert {:error, %Contract{}} = Jido.Chat.execute(binding, fact)
    refute_received {:callback, _, _}
  end

  test "logical request identity is separate from Signal ID and returns the same cached result" do
    binding = test_binding(Native)
    row = operation("send_message")
    first = request(binding, row)
    second = request(binding, row)
    refute first.id == second.id
    assert {:ok, result} = Jido.Chat.execute(binding, first)
    assert {:ok, ^result} = Jido.Chat.execute(binding, second)
    assert_received {:callback, :send_message, _}
    refute_received {:callback, _, _}
    changed = Jido.Chat.Signal.SendMessage.new!(Map.put(row["fixture"], "text", "different"))
    assert {:error, %Contract{code: :request_conflict}} = Jido.Chat.execute(binding, changed)
    refute_received {:callback, _, _}
  end

  test "fallback selection preserves explicit callback counts" do
    for name <- ["post_message", "post_channel_message", "fetch_metadata", "fetch_subject"] do
      binding = test_binding(Fallback)
      assert {:ok, result} = Jido.Chat.execute(binding, request(binding, operation(name)))
      assert result.type == Jido.Chat.Signal.OperationCompleted.type()

      expected =
        case name do
          "fetch_metadata" -> []
          "fetch_subject" -> [:fetch_thread]
          _ -> [:send_message]
        end

      for op <- expected, do: assert_received({:callback, ^op, _})
      refute_received {:callback, _, _}
    end
  end

  test "ephemeral DM fallback is explicit and invokes open then send once" do
    binding = test_binding(Fallback)
    row = operation("post_ephemeral")
    data = Map.put(row["fixture"], "fallback_to_dm", true)
    request = Jido.Chat.Signal.PostEphemeral.new!(data)
    assert {:ok, result} = Jido.Chat.execute(binding, request)
    assert result.type == Jido.Chat.Signal.OperationCompleted.type()
    assert_received {:callback, :open_dm, _}
    assert_received {:callback, :send_message, _}
    refute_received {:callback, _, _}
  end

  test "ephemeral DM fallback extracts the ID from a conversation result" do
    results = Map.put(@results, :open_dm, %{"id" => "dm-room", "kind" => "direct"})
    binding = test_binding(Fallback, results: results)
    data = Map.put(operation("post_ephemeral")["fixture"], "fallback_to_dm", true)
    request = Jido.Chat.Signal.PostEphemeral.new!(data)
    assert {:ok, result} = Jido.Chat.execute(binding, request)
    assert result.type == Jido.Chat.Signal.OperationCompleted.type()
    assert_received {:callback, :open_dm, _}
    assert_received {:callback, :send_message, ["dm-room", _, _]}
    assert {:ok, ^result} = Jido.Chat.execute(binding, request)
    refute_received {:callback, _, _}
  end

  test "ephemeral DM fallback rejects an invalid conversation before sending" do
    binding = test_binding(Fallback, results: Map.put(@results, :open_dm, %{"kind" => "direct"}))
    data = Map.put(operation("post_ephemeral")["fixture"], "fallback_to_dm", true)
    assert {:ok, result} = Jido.Chat.execute(binding, Jido.Chat.Signal.PostEphemeral.new!(data))
    assert result.data["code"] == "invalid_provider_result"
    assert_received {:callback, :open_dm, _}
    refute_received {:callback, :send_message, _}
  end

  test "typed messages retain canonical media in direct and paged results" do
    ref = %{
      "id" => "media-1",
      "scope" => "call",
      "binding_id" => "binding/alpha",
      "kind" => "media"
    }

    media = %{
      "kind" => "file",
      "name" => "report.txt",
      "media_type" => "text/plain",
      "caption" => "Report",
      "resource_ref" => ref
    }

    message = %{"id" => "message-1", "room_id" => "room/1", "media" => [media]}

    private_media =
      media
      |> Map.put("raw", "private-provider-value")
      |> Map.update!("resource_ref", &Map.put(&1, "raw", "private-reference-value"))

    private_message =
      message
      |> Map.put("raw", %{"token" => "private-provider-value"})
      |> Map.put("media", [private_media])

    for name <- ["send_message", "fetch_messages"] do
      operation = String.to_atom(name)

      value =
        if name == "send_message",
          do: private_message,
          else: %{"messages" => [private_message], "complete" => true}

      binding = test_binding(Native, results: Map.put(@results, operation, value))
      assert {:ok, result} = Jido.Chat.execute(binding, request(binding, operation(name)))
      assert result.type == Jido.Chat.Signal.OperationCompleted.type()

      selected =
        if name == "send_message",
          do: result.data["result"],
          else: hd(result.data["result"]["messages"])

      assert selected == message
      assert_received {:callback, ^operation, _}
      refute_received {:callback, _, _}
    end
  end

  test "typed thread results retain canonical delivery references and provider aliases" do
    for name <- ["fetch_thread", "list_threads", "open_thread"],
        key <- ["delivery_room_ref", "delivery_external_room_id"] do
      operation = String.to_atom(name)
      thread = %{"id" => "thread-1", "room_id" => "room/1", key => "thread-room"}

      value =
        if name == "list_threads", do: %{"threads" => [thread], "complete" => true}, else: thread

      binding = test_binding(Native, results: Map.put(@results, operation, value))
      assert {:ok, result} = Jido.Chat.execute(binding, request(binding, operation(name)))
      assert result.type == Jido.Chat.Signal.OperationCompleted.type()

      selected =
        if name == "list_threads",
          do: hd(result.data["result"]["threads"]),
          else: result.data["result"]

      assert selected["delivery_room_ref"] == "thread-room"
      refute Map.has_key?(selected, "delivery_external_room_id")
      assert_received {:callback, ^operation, _}
      refute_received {:callback, _, _}
    end
  end

  test "typed resource content keeps the selected fallback text in native payloads" do
    binding = test_binding(Native)
    observer = self()

    stream =
      Stream.map(["generated"], fn chunk ->
        send(observer, :enumerated)
        chunk
      end)

    for {kind, value} <- [
          {"card", Jido.Chat.Card.new(%{title: "Generated"})},
          {"stream", stream},
          {"media", Jido.Chat.FileUpload.new(%{data: "private", filename: "file.txt"})}
        ] do
      assert {:ok, ref} = Jido.Chat.put_resource(binding, kind, value)

      request =
        Jido.Chat.Signal.PostMessage.new!(%{
          "request_id" => "native-fallback-" <> kind,
          "room_id" => "room/1",
          "content" => %{
            "kind" => kind,
            "resource_ref" => ref,
            "fallback_text" => "Selected fallback"
          }
        })

      assert {:ok, _} = Jido.Chat.execute(binding, request)
      assert_received {:callback, :post_message, ["room/1", payload, _]}
      assert payload.fallback_text == "Selected fallback"
      assert Jido.Chat.PostPayload.display_text(payload) == "Selected fallback"
      if kind == "stream", do: assert(payload.stream == stream)
      refute_received :enumerated
    end
  end

  test "card and stream post fallbacks send the selected fallback text" do
    for {kind, value} <- [
          {"card", Jido.Chat.Card.new(%{title: "Generated"})},
          {"stream", Stream.map(["generated"], & &1)}
        ] do
      binding = test_binding(Fallback)
      assert {:ok, ref} = Jido.Chat.put_resource(binding, kind, value)

      request =
        Jido.Chat.Signal.PostMessage.new!(%{
          "request_id" => "selected-fallback",
          "room_id" => "room/1",
          "content" => %{
            "kind" => kind,
            "resource_ref" => ref,
            "fallback_text" => "Selected fallback"
          }
        })

      assert {:ok, _} = Jido.Chat.execute(binding, request)
      assert_received {:callback, :send_message, ["room/1", "Selected fallback", _]}
      refute_received {:callback, _, _}
    end
  end

  test "media post fallback uses selected text when no explicit caption is present" do
    for caption <- [nil, "Explicit caption"] do
      binding = test_binding(Fallback)
      file = Jido.Chat.FileUpload.new(%{data: "private", filename: "file.txt"})
      assert {:ok, ref} = Jido.Chat.put_resource(binding, "file", file)

      content = %{
        "kind" => "media",
        "resource_ref" => ref,
        "fallback_text" => "Selected fallback"
      }

      content = if caption, do: Map.put(content, "caption", caption), else: content

      request =
        Jido.Chat.Signal.PostMessage.new!(%{
          "request_id" => "media-fallback",
          "room_id" => "room/1",
          "content" => content
        })

      assert {:ok, _} = Jido.Chat.execute(binding, request)
      assert_received {:callback, :send_file, ["room/1", ^file, opts]}
      assert opts[:caption] == (caption || "Selected fallback")
      refute_received {:callback, _, _}
    end
  end

  test "native streams stay lazy until the provider consumes them" do
    binding = test_binding(Native)
    observer = self()

    stream =
      Stream.map(["one", "two"], fn value ->
        send(observer, {:enumerated, value})
        value
      end)

    assert {:ok, ref} = Jido.Chat.put_resource(binding, "stream", stream)
    request = Jido.Chat.Signal.Stream.new!(%{"request_id" => "request-1", "room_id" => "room/1", "resource_ref" => ref})
    assert {:ok, _} = Jido.Chat.execute(binding, request)
    assert_received {:callback, :stream, ["room/1", ^stream, _]}
    refute_received {:enumerated, _}
  end

  test "invalid provider data and exceptions never rerun the callback" do
    for {mode, code} <- [{:invalid, "invalid_provider_result"}, {:raise, "provider_failure"}] do
      binding = test_binding(Native, mode: mode)
      assert {:ok, result} = Jido.Chat.execute(binding, request(binding, operation("send_message")))
      assert result.data["code"] == code
      assert_received {:callback, :send_message, _}
      refute_received {:callback, _, _}
    end
  end

  test "paged queries retain every item and cursor without claiming completeness" do
    binding = test_binding(Native)
    assert {:ok, result} = Jido.Chat.execute(binding, request(binding, operation("fetch_messages")))
    assert result.data["result"]["messages"] == @results[:fetch_messages]["messages"]
    assert result.data["result"]["next_cursor"] == "page-2"
    assert result.data["result"]["complete"] == false
    assert_received {:callback, :fetch_messages, _}
    refute_received {:callback, _, _}
  end

  test "large selected results use an owner-bound reference and retain their cursor" do
    page = %{
      "messages" => [%{"id" => "large", "room_id" => "room/1", "text" => String.duplicate("x", 300_000)}],
      "next_cursor" => "next",
      "complete" => false
    }

    results = Map.put(@results, :fetch_messages, page)
    assert {:ok, binding} = Jido.Chat.bind(Native, id: "binding/alpha", notify: self(), results: results)
    assert {:ok, result} = Jido.Chat.execute(binding, request(binding, operation("fetch_messages")))
    ref = result.data["result"]["resource_ref"]
    assert ref["kind"] == "result"
    assert {:ok, ^page} = Jido.Chat.resolve_resource(binding, ref)
    assert_received {:callback, :fetch_messages, _}
    refute_received {:callback, _, _}
  end

  test "resource expiry, cancellation, and failure return typed results with zero callbacks" do
    for {state, code} <- [
          {:expired, "resource_expired"},
          {:cancelled, "resource_cancelled"},
          {:failed, "resource_failure"}
        ] do
      binding = test_binding(Native)
      opts = if state == :expired, do: [ttl_ms: 0], else: []
      assert {:ok, ref} = Jido.Chat.put_resource(binding, "file", Jido.Chat.FileUpload.new(%{data: "private"}), opts)
      if state == :cancelled, do: assert(:ok == Jido.Chat.cancel_resource(binding, ref))
      if state == :failed, do: assert(:ok == Jido.Chat.Resources.fail(binding, ref))

      request =
        Jido.Chat.Signal.SendFile.new!(%{"request_id" => "request-1", "room_id" => "room/1", "resource_ref" => ref})

      assert {:ok, result} = Jido.Chat.execute(binding, request)
      assert result.data["code"] == code
      refute_received {:callback, _, _}
    end
  end

  test "post/edit stream fallback preserves order and does not repeat the final edit" do
    binding = test_binding(Fallback)
    assert {:ok, ref} = Jido.Chat.put_resource(binding, "stream", ["one", "two"])
    request = Jido.Chat.Signal.Stream.new!(%{"request_id" => "request-1", "room_id" => "room/1", "resource_ref" => ref})
    assert {:ok, result} = Jido.Chat.execute(binding, request)
    assert result.type == Jido.Chat.Signal.OperationCompleted.type()
    assert_received {:callback, :send_message, ["room/1", "Working...", _]}
    assert_received {:callback, :edit_message, ["room/1", "message-1", "one", _]}
    assert_received {:callback, :edit_message, ["room/1", "message-1", "onetwo", _]}
    refute_received {:callback, _, _}
  end

  test "blank-placeholder stream fallback starts once at the first snapshot" do
    binding = test_binding(Fallback, placeholder_text: "")
    assert {:ok, ref} = Jido.Chat.put_resource(binding, "stream", ["one", "two"])
    request = Jido.Chat.Signal.Stream.new!(%{"request_id" => "request-1", "room_id" => "room/1", "resource_ref" => ref})
    assert {:ok, _} = Jido.Chat.execute(binding, request)
    assert_received {:callback, :send_message, ["room/1", "one", _]}
    assert_received {:callback, :edit_message, ["room/1", "message-1", "onetwo", _]}
    refute_received {:callback, _, _}
  end

  test "one file post fallback selects send_file once" do
    binding = test_binding(Fallback)
    file = Jido.Chat.FileUpload.new(%{data: "private", filename: "file.txt"})
    assert {:ok, ref} = Jido.Chat.put_resource(binding, "file", file)

    request =
      Jido.Chat.Signal.PostMessage.new!(%{
        "request_id" => "request-1",
        "room_id" => "room/1",
        "content" => %{"kind" => "media", "resource_ref" => ref, "caption" => "caption"}
      })

    assert {:ok, _} = Jido.Chat.execute(binding, request)
    assert_received {:callback, :send_file, ["room/1", ^file, opts]}
    assert opts[:caption] == "caption"
    refute_received {:callback, _, _}
  end

  test "an in-progress request cannot invoke a second callback" do
    binding = test_binding(Blocking)
    request = request(binding, operation("send_message"))
    first = Task.async(fn -> Jido.Chat.execute(binding, request) end)
    assert_receive {:provider_started, owner}
    assert {:error, %Contract{code: :request_in_progress}} = Jido.Chat.execute(binding, request)
    refute_received {:provider_started, _}
    send(owner, :release)
    assert {:ok, result} = Task.await(first)
    assert {:ok, ^result} = Jido.Chat.execute(binding, request)
    refute_received {:provider_started, _}
  end

  test "caller termination leaves unknown effect state and cannot trigger an automatic repeat" do
    binding = test_binding(Blocking)
    request = request(binding, operation("send_message"))
    caller = spawn(fn -> Jido.Chat.execute(binding, request) end)
    ref = Process.monitor(caller)
    assert_receive {:provider_started, ^caller}
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^ref, :process, ^caller, :killed}
    assert {:error, %Contract{code: :request_outcome_unknown}} = Jido.Chat.execute(binding, request)
    refute_received {:provider_started, _}
  end

  test "closing call-local state cannot erase an accepted provider result" do
    binding = test_binding(Blocking)
    request = request(binding, operation("send_message"))
    task = Task.async(fn -> Jido.Chat.execute(binding, request) end)
    assert_receive {:provider_started, owner}
    assert :ok = Jido.Chat.Resources.close(binding)
    send(owner, :release)
    assert {:ok, result} = Task.await(task)
    assert result.type == "jido.chat.operation.completed"
    assert {:error, %Contract{code: :invalid_binding}} = Jido.Chat.execute(binding, request)
    refute_received {:provider_started, _}
  end

  test "private fallback invocation preserves callback order and lazy resources" do
    alias Jido.Chat.Operations.Executor

    for name <- ["post_message", "post_channel_message", "fetch_metadata", "fetch_subject", "post_ephemeral", "stream"] do
      binding = test_binding(Fallback)
      row = operation(name)
      request = request(binding, row)

      request =
        if name == "post_ephemeral", do: %{request | data: Map.put(request.data, "fallback_to_dm", true)}, else: request

      assert {:ok, {:prepared, completion, invocation}} = Executor.prepare(binding, request)
      refute_received {:callback, _, _}
      outcome = Task.async(fn -> Executor.invoke(invocation) end) |> Task.await()
      assert {:ok, result} = Executor.complete(completion, outcome)
      assert result.type == Jido.Chat.Signal.OperationCompleted.type()
      assert {:ok, ^result} = Jido.Chat.execute(binding, request)

      expected =
        case name do
          "fetch_metadata" -> []
          "fetch_subject" -> [:fetch_thread]
          "post_ephemeral" -> [:open_dm, :send_message]
          "stream" -> [:send_message, :edit_message]
          _ -> [:send_message]
        end

      for op <- expected do
        assert_received {:callback, ^op, arguments}
        if name == "stream", do: refute(Keyword.has_key?(List.last(arguments), :fallback_mode))
      end

      refute_received {:callback, _, _}
    end
  end

  test "a dead provider becomes unknown while its completion owner stays alive" do
    alias Jido.Chat.Operations.Executor
    binding = test_binding(Blocking)
    request = request(binding, operation("send_message"))
    assert {:ok, {:prepared, completion, invocation}} = Executor.prepare(binding, request)
    {worker, monitor} = spawn_monitor(fn -> Executor.invoke(invocation) end)
    assert_receive {:provider_started, ^worker}, 1_000
    Process.exit(worker, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}, 1_000
    assert {:error, %Contract{code: :request_outcome_unknown}} = Executor.unknown(completion)
    assert {:error, %Contract{code: :request_outcome_unknown}} = Executor.complete(completion, {:ok, %{id: "late"}})
    assert {:error, %Contract{code: :request_outcome_unknown}} = Jido.Chat.execute(binding, request)

    assert {:error, %Contract{code: :request_conflict}} =
             Jido.Chat.execute(binding, %{request | data: Map.put(request.data, "text", "changed")})

    assert Process.alive?(self())
    refute_received {:provider_started, _}
  end

  defp test_binding(adapter, opts \\ []) do
    results = Map.put(@results, :open_dm, "dm-room")

    assert {:ok, binding} =
             Jido.Chat.bind(
               adapter,
               Keyword.merge([id: "binding/alpha", notify: self(), results: results], opts)
             )

    binding
  end

  defp operation(name), do: Enum.find(@operations, &(&1["operation"] == name))

  defp request(binding, row) do
    data = row["fixture"]

    data =
      case row["operation"] do
        "send_file" ->
          resource_data(
            binding,
            data,
            "resource_ref",
            "file",
            Jido.Chat.FileUpload.new(%{data: "private", filename: "file.txt"})
          )

        "fetch_media" ->
          resource_data(binding, data, "media_ref", "media", "private-provider-reference")

        "stream" ->
          resource_data(binding, data, "resource_ref", "stream", Stream.map(["hello"], & &1))

        "open_modal" ->
          resource_data(binding, data, "modal", "modal", Jido.Chat.Modal.new(%{title: "Title"}))

        _ ->
          data
      end

    module = Module.concat([row["request_module"]])
    value = module.new!(data)
    assert {:ok, value} = Trace.put(value, Trace.new())
    value
  end

  defp resource_data(binding, data, field, kind, value) do
    assert {:ok, ref} = Jido.Chat.put_resource(binding, kind, value)
    Map.put(data, field, ref)
  end
end
