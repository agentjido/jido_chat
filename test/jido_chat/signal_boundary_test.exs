defmodule Jido.Chat.SignalBoundaryTest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true

  alias Jido.Chat
  alias Jido.Chat.{Client, Delivery}
  alias Jido.Chat.Errors.Contract
  alias Jido.Chat.Signal.Policy
  alias Jido.Signal.Trace
  alias Jido.Tracing.Context, as: TraceContext
  alias Jido.Tracing.Trace, as: JidoTrace

  defmodule Fact do
    use Jido.Signal,
      type: "test.native.presence",
      dataschema: "urn:test:native:presence:1",
      default_source: "urn:test:provider",
      schema:
        Zoi.map(%{
          "item_id" => Zoi.string(),
          "delivery_id" => Zoi.string(),
          "room_id" => Zoi.string(),
          "metadata" => Zoi.map()
        })
  end

  defmodule Adapter do
    use Chat.Adapter
    def capabilities, do: %{send_message: :native, open_modal: :native}
    def event_definitions, do: [Fact]
    def normalize(_, _, _), do: {:error, :unused}

    def invoke(client, request, _opts) do
      send(client.config[:observer], {:invoked, request, TraceContext.get()})

      case request.type do
        "jido.chat.command.open_modal" -> {:ok, %{"opened" => true}}
        _ -> {:ok, %{"id" => "message", "room_id" => request.data["room_id"]}}
      end
    end
  end

  defp client, do: Client.new!(Adapter, id: "native", config: [observer: self()])
  defp data, do: %{"client_id" => "native", "request_id" => "r", "room_id" => "room", "text" => "Hello"}

  test "client configuration rejects explicit nil values and invalid field types" do
    assert {:ok, %Client{credentials: %{}, config: []}} = Client.new(Adapter, id: "native")

    for opts <- [[credentials: nil], [config: nil], [credentials: []], [config: %{}], [transport: "invalid"]] do
      assert {:error, %Contract{code: :invalid_client}} = Client.new(Adapter, [id: "native"] ++ opts)
    end
  end

  test "native facts need no Chat metadata and cannot bypass private data checks" do
    client = client()
    data = %{"item_id" => "item", "delivery_id" => "delivery", "room_id" => "room", "metadata" => %{}}
    opts = [source: client.source, subject: Chat.Signal.Identity.conversation_subject(client.id, "room")]
    fact = Fact.new!(data, opts)
    assert {:ok, %Delivery{signals: [^fact]}} = Delivery.new(client, "delivery", [fact])

    unsafe = %{fact | data: Map.put(fact.data, "token", "private")}
    assert {:ok, stripped} = Jido.Signal.Catalog.validate(Chat.catalog(client), unsafe)
    refute Map.has_key?(stripped.data, "token")
    assert {:error, %Contract{code: :unsafe_data}} = Delivery.new(client, "delivery", [unsafe])
    assert {:error, %Contract{code: :unsafe_data}} = Policy.new(Fact, unsafe.data, opts)

    for metadata <- [%{"token" => "example"}, %{"nested" => %{"secret" => "example"}}, %{bad: "value"}] do
      unsafe = Fact.new!(%{data | "metadata" => metadata}, opts)
      assert {:ok, _} = Jido.Signal.Catalog.validate(Chat.catalog(client), unsafe)
      assert {:error, %Contract{code: :unsafe_data}} = Delivery.new(client, "delivery", [unsafe])
    end
  end

  test "SDK execution carries Jido context into the execution task and native result context" do
    parent = Policy.new!(Chat.Signal.SendMessage, data())
    {:ok, parent} = Trace.put(parent, Trace.new(trace_flags: "01", tracestate: "vendor=example"))
    context = JidoTrace.get(parent)
    previous = TraceContext.get()

    completed =
      TraceContext.with_context(context, fn ->
        assert {:ok, result} = Chat.send_text(client(), "room", "Hello")
        result
      end)

    assert TraceContext.get() == previous
    assert_receive {:invoked, request, execution_context}
    assert execution_context.traceparent == context.traceparent
    assert Trace.get(request) == Trace.get(parent)
    assert Trace.get(completed) == Trace.get(parent)
    assert JidoTrace.get(completed).causation_id == request.id
    refute Map.has_key?(completed.extensions, "causationid")
  end

  test "explicit request context overrides ambient context and direct Actions receive it" do
    request = Policy.new!(Chat.Signal.SendMessage, data())
    ambient = JidoTrace.new_root()

    TraceContext.with_context(ambient, fn ->
      assert {:ok, %{signal: completed}} = Jido.Exec.run(Chat.SendMessage, %{signal: request}, %{client: client()})
      assert Trace.get(completed) == Trace.get(request)
      assert TraceContext.get() == ambient
    end)

    assert_receive {:invoked, ^request, execution_context}
    assert execution_context.traceparent == request.extensions["traceparent"]
    refute execution_context.trace_id == ambient.trace_id
  end

  test "native constructors retain native errors and Chat construction enforces Chat policy" do
    assert {:error, errors} = Chat.Signal.SendMessage.new(%{data() | "text" => 42})
    assert is_list(errors)
    assert {:error, %Contract{}} = Policy.new(Chat.Signal.SendMessage, %{data() | "text" => 42})

    for context <- [%{"causationid" => "old"}, %{"traceparent" => "invalid"}, %{"tracestate" => "vendor=orphan"}] do
      assert {:error, %Contract{code: :invalid_context}} =
               Policy.new(Chat.Signal.SendMessage, data(), extensions: context)
    end
  end

  test "modal payloads use the model rules before provider execution" do
    base = data() |> Map.delete("text")

    for modal <- [
          %{},
          %{"title" => "Form", "elements" => [%{"kind" => "unknown", "id" => "input"}]},
          %{
            "title" => "Form",
            "elements" => [%{"kind" => "text_input", "id" => "input", "min_length" => 5, "max_length" => 1}]
          }
        ] do
      request =
        Jido.Signal.new!(Chat.Signal.OpenModal.type(), Map.put(base, "modal", modal),
          source: "urn:test",
          dataschema: Chat.Signal.OpenModal.dataschema()
        )

      assert {:error, _} = Chat.execute(client(), request)
    end

    refute_receive {:invoked, _, _}
    modal = Chat.Modal.new(%{title: "Form", elements: [Chat.Modal.text_input("input", "Name")]})
    request = Policy.new!(Chat.Signal.OpenModal, Map.put(base, "modal", Chat.Modal.to_map(modal)))
    assert {:ok, _} = Chat.execute(client(), request)
    assert_receive {:invoked, _, _}
  end
end
