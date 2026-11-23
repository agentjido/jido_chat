defmodule Jido.Chat.APIHardeningTest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true
  alias Jido.Chat
  alias Jido.Chat.{Client, Delivery}
  alias Jido.Chat.Operations.Definition

  defmodule ProviderFact do
    use Jido.Signal,
      type: "test.chat.presence.changed",
      dataschema: "urn:test:presence:1",
      default_source: "urn:test:producer",
      schema:
        Jido.Joi.map(
          %{
            "item_id" => Jido.Joi.string(),
            "delivery_id" => Jido.Joi.string(),
            "room_id" => Jido.Joi.string(),
            "online" => Jido.Joi.boolean()
          },
          unrecognized_keys: :error
        )
  end

  defmodule ProviderRequest do
    use Jido.Signal,
      type: "test.chat.query.status",
      default_source: "urn:test:producer",
      schema:
        Jido.Joi.map(
          %{
            "client_id" => Jido.Joi.string(),
            "request_id" => Jido.Joi.string() |> Jido.Joi.transform({__MODULE__, :normalize_id, []})
          },
          unrecognized_keys: :error
        )

    def normalize_id(value, _opts), do: String.trim(value)
  end

  defmodule ProviderAccepted do
    use Jido.Signal,
        Definition.completion_options(
          ProviderRequest,
          Jido.Joi.map(%{"online" => Jido.Joi.boolean()}, unrecognized_keys: :error)
        )
        |> Keyword.put(:type, "test.chat.status.ready")
  end

  defmodule ProviderDeclined do
    use Jido.Signal, Definition.failure_options(ProviderRequest)
  end

  defmodule ProviderAction do
    use Jido.Action,
      name: "test_status",
      schema: ProviderRequest.schema(),
      output_schema: ProviderAccepted.schema()

    @definition %Definition{
      action: __MODULE__,
      request: ProviderRequest,
      completed: ProviderAccepted,
      failed: ProviderDeclined,
      result_schema: Jido.Joi.map(%{"online" => Jido.Joi.boolean()}, unrecognized_keys: :error)
    }

    def definition, do: @definition

    @impl Jido.Action
    def run(params, context), do: Definition.run(@definition, params, context)
  end

  defmodule Adapter do
    use Jido.Chat.Adapter
    def channel_type, do: :test

    def capabilities,
      do: %{send_message: :native, download_file: :native, fetch_metadata: :native, create_thread: :native}

    def operation_definitions, do: [ProviderAction.definition()]
    def event_definitions, do: [ProviderFact]
    def normalize(_, input, _), do: {:ok, input}

    def invoke(client, request, opts) do
      send(client.config[:observer], {:invoked, request.type, opts})
      if opts[:wait], do: Process.sleep(opts[:wait])
      Keyword.get(opts, :response, {:ok, %{"id" => "message", "room_id" => "room"}})
    end
  end

  defmodule InvalidOperationAdapter do
    use Jido.Chat.Adapter
    defdelegate channel_type(), to: Adapter
    defdelegate capabilities(), to: Adapter
    defdelegate invoke(client, signal, opts), to: Adapter
    defdelegate normalize(client, input, opts), to: Adapter

    def operation_definitions, do: [%{ProviderAction.definition() | result_schema: nil}]
  end

  defmodule Unsupported do
    use Jido.Chat.Adapter
    def channel_type, do: :unsupported
    def capabilities, do: %{}
    def normalize(_, _, _), do: {:error, :unused}

    def invoke(client, _, _) do
      send(client.config[:observer], :unexpected_provider_call)
      raise "Provider must not run"
    end
  end

  defmodule InvalidAdapter do
    use Jido.Chat.Adapter
    def channel_type, do: :invalid
    def capabilities, do: %{bad_key: :invalid}
    def normalize(_, _, _), do: {:error, :unused}
    def invoke(_, _, _), do: {:error, :unused}
  end

  defp client(adapter \\ Adapter), do: Client.new!(adapter, id: "test", config: [observer: self()])

  defp request do
    Jido.Chat.Signal.Policy.new!(Chat.Signal.SendMessage, %{
      "client_id" => "test",
      "request_id" => "r",
      "room_id" => "room",
      "text" => "Hello"
    })
  end

  test "Action schemas expose the data accepted by native execution" do
    schema = Chat.SendMessage.authoring_contract()["input_schema"]
    assert schema["additionalProperties"] == false
    assert schema["properties"]["room_id"]["type"] == "string"
    assert "text" in schema["required"]
    data = request().data |> Jason.encode!() |> Jason.decode!()
    assert {:ok, completed} = Jido.Exec.run(Chat.SendMessage, data, %{client: client()})
    assert completed["request_id"] == "r"
    assert_receive {:invoked, _, []}

    for invalid <- [
          %{request() | type: "wrong"},
          put_in(request(), [Access.key(:data), "text"], 42),
          %{request() | data: Map.put(data, "token", "private")}
        ] do
      assert {:error, _} = Chat.execute(client(), invalid)
    end

    refute_receive {:invoked, _, _}
    assert {:error, _} = Chat.SendMessage.validate_params(nil)
    output = Chat.SendMessage.authoring_contract()["output_schema"]
    assert output["properties"]["result"]["properties"]["id"]["type"] == "string"
  end

  test "invalid downloads and incomplete metadata or created threads cannot complete" do
    ref = %{"client_id" => "test", "kind" => "media", "id" => "file"}

    cases = [
      {:download_file, [ref], %{"content_base64" => "not base64"}},
      {:fetch_metadata, ["room"], %{"id" => "room"}},
      {:create_thread, ["room", "Topic"], %{"id" => "thread", "room_id" => "room"}}
    ]

    for {operation, args, result} <- cases do
      assert {:error, %Chat.Error{code: :invalid_provider_result}} =
               apply(Chat, operation, [client() | args] ++ [[options: [response: {:ok, result}]]])

      assert_receive {:invoked, _, _}
    end

    for bytes <- ["", <<0, 255, 1>>] do
      encoded = Base.encode64(bytes)

      assert {:ok, completed} =
               Chat.download_file(client(), ref, options: [response: {:ok, %{"content_base64" => encoded}}])

      assert completed.data["result"]["content_base64"] == encoded
      assert_receive {:invoked, _, _}
    end
  end

  test "execution deadlines return a safe failure and do not retry" do
    assert {:error, %Chat.Error{code: :timeout, signal: failed}} =
             Chat.send_text(client(), "room", "Hello", timeout: 100, options: [wait: 500])

    assert failed.data["outcome"] == "unknown"
    assert_receive {:invoked, _, [wait: 500]}
    refute_receive {:invoked, _, _}
    assert {:ok, _} = Chat.execute(client(), request(), timeout: :infinity)
    assert_receive {:invoked, _, []}

    for opts <- [[timeout: -1], [timeout: "20"], [timeout: 1, timeout: 2], [options: :bad], [old_private: true]] do
      assert {:error, _} = Chat.execute(client(), request(), opts)
    end

    assert {:error, _} = Chat.send_text(client(), "room", "Hello", timeout: -1)
    refute_receive {:invoked, _, _}
  end

  test "an oversized completion returns a typed failure after one provider call" do
    client = client()
    request = request()
    large_result = %{"id" => "message", "room_id" => "room", "text" => String.duplicate("x", 270_000)}

    assert {:error, %Chat.Error{code: :invalid_provider_result, signal: failed}} =
             Chat.execute(client, request, options: [response: {:ok, large_result}])

    assert failed.type == Chat.SendMessage.Failed.type()
    assert failed.data["outcome"] == "unknown"
    assert failed.extensions["jidocausationid"] == request.id
    assert_receive {:invoked, _, _}
    refute_received {:invoked, _, _}
  end

  test "a completion cannot use a different request as its parent" do
    client = client()
    first = request()
    second = Chat.Signal.SendMessage.new!(%{first.data | "request_id" => "second"})
    assert {:ok, data} = Jido.Exec.run(Chat.SendMessage, first.data, %{client: client, signal: first})
    assert {:error, %Chat.Errors.Contract{code: :context_mismatch}} = Chat.SendMessage.reply(second, data)
    assert {:ok, completed} = Chat.SendMessage.reply(first, data)
    assert completed.extensions["jidocausationid"] == first.id
  end

  test "safe error categories preserve outcome and bounded retry hints without provider details" do
    for code <- [:unauthorized, :forbidden, :not_found, :rate_limited, :timeout] do
      assert {:error, %Chat.Error{code: ^code, signal: failed}} =
               Chat.send_text(client(), "room", "Hello",
                 options: [response: {:error, {:rejected, code, %{retry_after_ms: 2000, raw: "private"}}}]
               )

      assert failed.data["outcome"] == "rejected"
      assert failed.data["retry_after_ms"] == 2000
      refute inspect(failed) =~ "private"
      assert_receive {:invoked, _, _}
    end

    assert {:error, %Chat.Error{signal: failed}} =
             Chat.send_text(client(), "room", "Hello",
               options: [response: {:error, {:rejected, :unknown_code, %{retry_after_ms: -1}}}]
             )

    assert failed.data["code"] == "provider_failure"
    refute Map.has_key?(failed.data, "retry_after_ms")
  end

  test "configured operations and incoming provider facts share the native catalog" do
    client = client()
    assert {ProviderRequest, ProviderAction} in Chat.operations(client)
    assert ProviderAction in Chat.actions(client)
    assert ProviderFact in Chat.signal_definitions(client)
    assert Chat.event_definitions(client) == [ProviderFact]
    request = ProviderRequest.new!(%{"client_id" => client.id, "request_id" => "status"})
    request = put_in(request.data["request_id"], " status ")
    assert {:ok, completed} = Chat.execute(client, request, options: [response: {:ok, %{"online" => true}}])
    assert completed.type == "test.chat.status.ready"
    assert is_nil(completed.dataschema)
    assert completed.data["request_id"] == "status"
    assert {:ok, _} = Jido.Signal.Catalog.validate(Chat.catalog(client), completed)

    assert {:error, %Chat.Error{signal: failed}} =
             Chat.execute(client, request, options: [response: {:error, {:rejected, :forbidden}}])

    assert failed.type == ProviderDeclined.type()
    assert is_nil(failed.dataschema)
    assert {:ok, _} = Jido.Signal.Catalog.validate(Chat.catalog(client), failed)

    fact =
      ProviderFact.new!(%{"delivery_id" => "delivery", "item_id" => "item", "room_id" => "room", "online" => true},
        source: client.source,
        subject: Chat.Signal.Identity.conversation_subject(client.id, "room")
      )

    assert {:ok, delivery} = Delivery.new(client, "delivery", [fact])
    assert {:ok, ^delivery} = Chat.normalize(client, delivery)
    assert {:error, _} = Delivery.new(client(Unsupported), "delivery", [fact])
    core_fact = Chat.AdapterTestKit.Factories.message_received(client, %{"delivery_id" => "delivery"})
    assert {:error, _} = Delivery.new(client, "delivery", [core_fact])
  end

  test "native operation registration rejects an invalid result schema" do
    assert {:error, %Chat.Errors.Contract{code: :invalid_capabilities}} =
             Chat.Adapter.validate_capabilities(InvalidOperationAdapter)

    assert {:error, %Chat.Errors.Contract{code: :invalid_client}} = Client.new(InvalidOperationAdapter, id: "invalid")
  end

  test "the adapter kit executes unsupported requests without calling the provider" do
    assert :ok = Chat.AdapterTestKit.Assertions.assert_unsupported_operations(client(Unsupported))
    assert :ok = Chat.AdapterTestKit.Assertions.assert_unsupported_operations(Unsupported)
    refute_receive :unexpected_provider_call
    assert {:error, _} = Client.new(InvalidAdapter, id: "bad")
  end
end
