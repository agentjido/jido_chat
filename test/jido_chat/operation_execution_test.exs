defmodule Jido.Chat.OperationExecutionTest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true
  alias Jido.Chat.Client
  alias Jido.Chat.Operations.Definition
  alias Jido.Signal.{Catalog, Codec}

  defmodule AssetRequest do
    use Jido.Signal,
      type: "example.chat.command.send_asset",
      dataschema: "urn:example:chat:send_asset:1",
      default_source: "urn:example:producer",
      schema:
        Jido.Joi.map(
          %{
            "client_id" => Jido.Joi.string() |> Jido.Joi.min(1),
            "request_id" => Jido.Joi.string() |> Jido.Joi.min(1),
            "room_id" => Jido.Joi.string() |> Jido.Joi.min(1),
            "attachments" => Jido.Joi.array(Jido.Chat.Signal.Schemas.reference()),
            "metadata" => Jido.Joi.any() |> Jido.Joi.optional()
          },
          unrecognized_keys: :error
        )
  end

  defmodule AssetCompleted do
    @result_schema Jido.Joi.map(
                     %{
                       "asset_id" => Jido.Joi.string() |> Jido.Joi.min(1),
                       "room_id" => Jido.Joi.string() |> Jido.Joi.min(1),
                       "reference" => Jido.Chat.Signal.Schemas.reference() |> Jido.Joi.optional()
                     },
                     unrecognized_keys: :error
                   )
    use Jido.Signal, Definition.completion_options(AssetRequest, @result_schema)

    def result_schema, do: @result_schema
  end

  defmodule AssetFailed do
    use Jido.Signal, Definition.failure_options(AssetRequest)
  end

  defmodule SendAsset do
    use Jido.Action,
      name: "example_send_asset",
      description: "Sends an asset through an external adapter",
      schema: AssetRequest.schema(),
      output_schema: AssetCompleted.schema()

    @definition %Definition{
      action: __MODULE__,
      request: AssetRequest,
      completed: AssetCompleted,
      failed: AssetFailed,
      result_schema: AssetCompleted.result_schema()
    }

    def definition, do: @definition

    @impl Jido.Action
    def run(params, context), do: Definition.run(@definition, params, context)
  end

  defmodule Adapter do
    use Jido.Chat.Adapter
    def channel_type, do: :test
    def capabilities, do: %{}
    def operation_definitions, do: [SendAsset.definition()]
    def normalize(_, _, _), do: {:error, :unused}

    def invoke(client, signal, opts) do
      send(opts[:observer], {:provider, client.id, signal.id})

      case opts[:response] do
        :raise -> raise "private provider failure"
        :throw -> throw("private provider failure")
        nil -> {:ok, %{"asset_id" => "a1", "room_id" => signal.data["room_id"]}}
        response -> response
      end
    end
  end

  defp client, do: Client.new!(Adapter, id: "example", credentials: %{token: "private"})

  defp execute(signal, options) do
    Jido.Exec.run(SendAsset, signal.data, %{client: client(), signal: signal, options: options}, max_attempts: 1)
  end

  defp request do
    signal =
      AssetRequest.new!(%{
        "client_id" => "example",
        "request_id" => "asset-1",
        "room_id" => "room-1",
        "attachments" => [%{"client_id" => "example", "id" => "file-1", "kind" => "file"}]
      })

    {:ok, signal, _} = Jido.Signal.Context.ensure_trace(signal)
    %{signal | extensions: Map.put(signal.extensions, "tracestate", "example=state")}
  end

  test "an extension delegates to its adapter without a core registry entry" do
    signal = request()
    assert is_nil(Jido.Chat.Operations.Definitions.lookup(signal.type))
    refute AssetRequest in Jido.Chat.signal_definitions()

    client = client()
    assert {AssetRequest, SendAsset} in Jido.Chat.operations(client)
    assert {:ok, completed} = Jido.Chat.execute(client, signal, options: [observer: self()])

    assert_receive {:provider, "example", _}
    assert completed.type == signal.type <> ".completed"
    assert completed.dataschema == signal.dataschema <> ":completed"
    assert completed.data["operation"] == signal.type
    assert completed.data["result"] == %{"asset_id" => "a1", "room_id" => "room-1"}
    assert completed.source == client().source
    assert completed.subject == Jido.Chat.Signal.Identity.conversation_subject("example", "room-1")
    assert completed.extensions["jidocausationid"] == signal.id
    assert completed.extensions["traceparent"] == signal.extensions["traceparent"]
    assert completed.extensions["tracestate"] == signal.extensions["tracestate"]

    catalog = Jido.Chat.catalog(client)
    assert {:ok, encoded} = Codec.serialize(completed)
    assert {:ok, ^completed} = Catalog.decode(catalog, encoded)
    assert SendAsset.description() == "Sends an asset through an external adapter"
    assert {:ok, _} = Jason.encode(SendAsset.authoring_contract())
    assert {:error, _} = SendAsset.validate_output(%{signal: signal})
    assert {:error, _} = SendAsset.validate_params(%{signal: Map.from_struct(signal)})
  end

  test "extension scope, exact schemas, private data, and options fail before provider I/O" do
    signal = request()

    for invalid <- [
          %{signal | dataschema: signal.dataschema <> ":unknown"},
          %{signal | subject: "another-room"},
          %{signal | data: Map.put(signal.data, "client_id", "other")},
          %{signal | data: Map.put(signal.data, "metadata", %{"token" => "private"})},
          %{signal | data: Map.put(signal.data, "metadata", self())},
          %{
            signal
            | data:
                Map.put(signal.data, "metadata", %{
                  "id" => "container",
                  "client_id" => "example",
                  "kind" => "file",
                  "child" => %{"id" => "foreign", "client_id" => "other", "kind" => "media"}
                })
          },
          put_in(signal.data["attachments"], [%{"id" => "file-1", "client_id" => "other", "kind" => "file"}])
        ] do
      assert {:error, _} = execute(invalid, observer: self())
    end

    assert {:error, _} = execute(signal, [:invalid])
    refute_receive {:provider, _, _}
  end

  test "extension provider failures are safe typed Signals with the original context" do
    signal = request()

    for {response, code, outcome} <- [
          {{:error, {:not_attempted, :unsupported}}, :unsupported, "not_attempted"},
          {{:error, {:not_attempted, :missing_token}}, :provider_failure, "not_attempted"},
          {{:error, {:rejected, "private"}}, :provider_failure, "rejected"},
          {{:error, "private"}, :provider_failure, "unknown"},
          {:raise, :provider_failure, "unknown"},
          {:throw, :provider_failure, "unknown"}
        ] do
      assert {:error, %Jido.Chat.Error{code: ^code, signal: failed}} =
               execute(signal, observer: self(), response: response)

      assert_receive {:provider, "example", _}
      assert failed.type == signal.type <> ".failed"
      assert failed.data["outcome"] == outcome
      assert failed.extensions["jidocausationid"] == signal.id
      assert failed.extensions["traceparent"] == signal.extensions["traceparent"]
      assert failed.extensions["tracestate"] == signal.extensions["tracestate"]
      assert {:ok, ^failed} = Catalog.validate(Jido.Chat.catalog(client()), failed)
      refute inspect(failed) =~ "private"
    end

    refute_receive {:provider, _, _}
  end

  test "invalid extension results and foreign result references cannot become completions" do
    for result <- [
          %{"asset_id" => 42, "room_id" => "room-1"},
          %{"asset_id" => "a1", "room_id" => "other"},
          %{
            "asset_id" => "a1",
            "room_id" => "room-1",
            "reference" => %{"id" => "file-1", "client_id" => "other", "kind" => "file"}
          }
        ] do
      assert {:error, %Jido.Chat.Error{code: :invalid_provider_result, signal: failed}} =
               execute(request(), observer: self(), response: {:ok, result})

      assert failed.type == AssetFailed.type()
      assert_receive {:provider, _, _}
    end
  end

  test "request context cannot describe different Action parameters" do
    request = request()
    params = Map.put(request.data, "room_id", "another-room")

    assert {:error, _} =
             Jido.Exec.run(SendAsset, params, %{client: client(), signal: request, options: [observer: self()]})

    refute_received {:provider, _, _}
  end
end
