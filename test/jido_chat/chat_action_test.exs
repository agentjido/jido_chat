defmodule Jido.Chat.ChatActionTest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true
  alias Jido.Chat.Client
  alias Jido.Chat.ContractFixtures, as: F
  alias Jido.Signal.{Catalog, Serialization, Trace}

  defmodule AssetRequest do
    use Jido.Signal,
      type: "example.chat.command.send_asset",
      dataschema: "urn:example:chat:send_asset:1",
      default_source: "urn:example:producer",
      schema:
        Zoi.map(
          %{
            "client_id" => Zoi.string() |> Zoi.min(1),
            "request_id" => Zoi.string() |> Zoi.min(1),
            "room_id" => Zoi.string() |> Zoi.min(1),
            "attachments" => Zoi.array(Jido.Chat.Signal.Schemas.reference()),
            "metadata" => Zoi.any() |> Zoi.optional()
          },
          unrecognized_keys: :error
        )
  end

  defmodule SendAsset do
    use Jido.ChatAction,
      name: "example_send_asset",
      description: "Sends an asset through an external adapter",
      signal: AssetRequest,
      result_schema:
        Zoi.map(
          %{
            "asset_id" => Zoi.string() |> Zoi.min(1),
            "room_id" => Zoi.string() |> Zoi.min(1),
            "reference" => Jido.Chat.Signal.Schemas.reference() |> Zoi.optional()
          },
          unrecognized_keys: :error
        )
  end

  defmodule InlineAsset do
    use Jido.ChatAction,
      name: "inline_asset",
      description: "Define both Signal contracts inline",
      vsn: 1,
      input: [
        type: "example.asset.create",
        default_source: "urn:example:caller",
        schema:
          Jido.Chat.Signal.Schemas.object(%{
            "client_id" => Jido.Chat.Signal.Schemas.id(),
            "request_id" => Jido.Chat.Signal.Schemas.id(),
            "room_id" => Jido.Chat.Signal.Schemas.id()
          })
      ],
      output: [
        type: "example.asset.ready",
        schema:
          Jido.Chat.Signal.Schemas.completion(
            "example.asset.create",
            Zoi.map(%{"asset_id" => Zoi.string(), "room_id" => Zoi.string()})
          )
      ],
      result_schema: Zoi.map(%{"asset_id" => Zoi.string(), "room_id" => Zoi.string()})
  end

  defmodule Adapter do
    use Jido.Chat.Adapter
    def capabilities, do: %{}
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

  defp request do
    signal =
      AssetRequest.new!(%{
        "client_id" => "example",
        "request_id" => "asset-1",
        "room_id" => "room-1",
        "attachments" => [%{"client_id" => "example", "id" => "file-1", "kind" => "file"}]
      })

    {:ok, signal, _} = Trace.ensure(signal)
    %{signal | extensions: Map.put(signal.extensions, "tracestate", "example=state")}
  end

  test "an extension delegates to its adapter without a core registry entry" do
    signal = request()
    assert is_nil(Jido.Chat.Operations.Definitions.lookup(signal.type))
    refute AssetRequest in Jido.Chat.signal_definitions()

    assert {:ok, %{signal: completed}} =
             F.execute(SendAsset, signal, %{client: client(), options: [observer: self()]})

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

    catalog = Catalog.new!(Jido.Chat.signal_definitions() ++ SendAsset.signal_definitions())
    assert {:ok, encoded} = Serialization.serialize(completed)
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
      assert {:error, _} =
               F.execute(SendAsset, invalid, %{client: client(), options: [observer: self()]})
    end

    assert {:error, _} = F.execute(SendAsset, signal, %{client: client(), options: [:invalid]})
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
               F.execute(SendAsset, signal, %{
                 client: client(),
                 options: [observer: self(), response: response]
               })

      assert_receive {:provider, "example", _}
      assert failed.type == signal.type <> ".failed"
      assert failed.data["outcome"] == outcome
      assert failed.extensions["jidocausationid"] == signal.id
      assert failed.extensions["traceparent"] == signal.extensions["traceparent"]
      assert failed.extensions["tracestate"] == signal.extensions["tracestate"]
      assert {:ok, ^failed} = Catalog.validate(Catalog.new!(SendAsset.signal_definitions()), failed)
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
               F.execute(SendAsset, request(), %{
                 client: client(),
                 options: [observer: self(), response: {:ok, result}]
               })

      assert failed.type == SendAsset.Failed.type()
      assert_receive {:provider, _, _}
    end
  end

  test "inline contracts use the explicit output type without a schema URI" do
    request = InlineAsset.new!(%{"client_id" => "example", "request_id" => "inline-1", "room_id" => "room-1"})
    assert InlineAsset.signal_definition() == InlineAsset
    assert InlineAsset.dataschema() == nil
    assert InlineAsset.Completed.dataschema() == nil
    assert InlineAsset.Failed.dataschema() == nil

    assert {:ok, data} =
             Jido.Exec.run(InlineAsset, request.data, %{client: client(), signal: request, options: [observer: self()]})

    assert_receive {:provider, "example", _}
    assert {:ok, reply} = InlineAsset.reply(request, data, source: client().source)
    assert reply.type == "example.asset.ready"
    assert reply.dataschema == nil
    assert {:ok, ^reply} = Catalog.validate(Catalog.new!(InlineAsset.signal_definitions()), reply)
  end

  test "request context cannot describe different Action parameters" do
    request = request()
    params = Map.put(request.data, "room_id", "another-room")

    assert {:error, _} =
             Jido.Exec.run(SendAsset, params, %{client: client(), signal: request, options: [observer: self()]})

    refute_received {:provider, _, _}
  end

  test "an extension must declare its result schema" do
    assert_raise ArgumentError, ~r/requires :result_schema/, fn ->
      Code.compile_string("""
      defmodule MissingChatResultSchema do
        use Jido.ChatAction,
          name: "missing_result_schema",
          signal: Jido.Chat.ChatActionTest.AssetRequest
      end
      """)
    end
  end
end
