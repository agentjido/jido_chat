defmodule Jido.Chat.StaticSDKTest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true
  alias Jido.Chat.ContractFixtures, as: F

  alias Jido.Chat.{Client, SendMessage}
  alias Jido.Chat.Signal

  defmodule Adapter do
    use Jido.Chat.Adapter
    def channel_type, do: :test
    def capabilities, do: %{send_message: :native}

    def invoke(client, signal, opts) do
      send(opts[:observer], {:invoked, client.id, signal.data})

      case opts[:response] do
        nil -> {:ok, %{"id" => "message-1", "room_id" => signal.data["room_id"], "text" => signal.data["text"]}}
        result -> result
      end
    end

    def normalize(client, payload, _opts), do: Jido.Chat.Delivery.new(client, payload.id, payload.signals)
  end

  defp client(id \\ "test") do
    Client.new!(Adapter, id: id, credentials: %{token: "private-token"})
  end

  defp command(client, data \\ %{}) do
    Signal.SendMessage.new!(
      Map.merge(
        %{"client_id" => client.id, "request_id" => "request-1", "room_id" => "room-1", "text" => "hello"},
        data
      )
    )
  end

  test "client construction owns no processes or ETS tables and hides private values" do
    before = owned_tables()
    client = client()
    assert owned_tables() == before
    assert client.credentials == %{token: "private-token"}
    refute inspect(client) =~ "private-token"
    assert {:ok, changed} = Client.new(Adapter, id: "other", credentials: %{token: "other"})
    assert changed.id == "other"
    assert client.id == "test"
  end

  test "the native Action validates and returns a result Signal" do
    client = client()
    request = command(client)

    assert {:ok, %{signal: result}} =
             F.execute(SendMessage, request, %{client: client, options: [observer: self()]})

    assert_receive {:invoked, "test", _}
    assert result.type == Jido.Chat.SendMessage.Completed.type()
    assert result.source == client.source
    assert result.data["result"]["id"] == "message-1"
    assert result.data["request_id"] == "request-1"
    assert result.extensions["jidocausationid"] == request.id
    assert {:ok, ^result} = Jido.Signal.Catalog.validate(Jido.Chat.catalog(), result)

    other_operation = %{result | data: Map.put(result.data, "operation", "edit_message")}
    assert {:error, _} = Jido.Signal.Catalog.validate(Jido.Chat.catalog(), other_operation)
    assert {:error, _} = SendMessage.validate_output(other_operation.data)
  end

  test "execute and the convenience function use the same Action" do
    client = client()

    assert {:ok, result} =
             Jido.Chat.send_message(client, %{"request_id" => "r", "room_id" => "room-1", "text" => "hello"},
               options: [observer: self()]
             )

    assert result.type == Jido.Chat.SendMessage.Completed.type()
    assert_receive {:invoked, "test", _}
    request = command(client)
    assert {:ok, _} = Jido.Chat.execute(client, request, options: [observer: self()])
    assert_receive {:invoked, "test", _}
  end

  test "media details remain portable and private metadata is rejected" do
    media = %{
      "kind" => "video",
      "resource_ref" => %{"client_id" => "test", "id" => "provider-file", "kind" => "media"},
      "width" => 240,
      "height" => 240,
      "duration" => 1.5,
      "metadata" => %{"telegram" => %{"is_video" => false}}
    }

    response = %{"id" => "message-1", "room_id" => "room-1", "media" => [media]}

    assert {:ok, completed} =
             Jido.Chat.execute(client(), command(client()), options: [observer: self(), response: {:ok, response}])

    assert completed.data["result"]["media"] == [media]
    assert {:ok, json} = Jido.Signal.Serialization.serialize(completed)
    assert {:ok, ^completed} = Jido.Signal.Catalog.decode(Jido.Chat.catalog(), json)

    unsafe = put_in(response, ["media"], [Map.put(media, "metadata", %{"token" => "private"})])

    assert {:error, %Jido.Chat.Error{code: :invalid_provider_result}} =
             Jido.Chat.execute(client(), command(client()), options: [observer: self(), response: {:ok, unsafe}])
  end

  test "repeated requests invoke the provider again without a request store" do
    client = client()
    request = command(client)
    for _ <- 1..2, do: assert({:ok, _} = Jido.Chat.execute(client, request, options: [observer: self()]))
    assert_receive {:invoked, "test", _}
    assert_receive {:invoked, "test", _}
  end

  test "invalid data, wrong schemas and client scope fail before provider I/O" do
    client = client()
    request = command(client)

    for invalid <- [
          %{request | data: Map.put(request.data, "text", 42)},
          %{request | dataschema: "wrong"},
          command(client("other"))
        ] do
      assert {:error, _} = Jido.Chat.execute(client, invalid, options: [observer: self()])
    end

    refute_receive {:invoked, _, _}
  end

  test "provider failures retain a safe failure Signal and stop Action execution" do
    assert {:error, %Jido.Chat.Error{signal: failed}} =
             Jido.Chat.execute(client(), command(client()),
               options: [observer: self(), response: {:error, "secret-provider-body"}]
             )

    assert failed.type == Jido.Chat.SendMessage.Failed.type()
    assert failed.data["outcome"] == "unknown"
    refute inspect(failed) =~ "secret-provider-body"
    assert_receive {:invoked, _, _}
    refute_receive {:invoked, _, _}
  end

  test "invalid provider results are errors and unsupported calls do not invoke adapters" do
    assert {:error, %Jido.Chat.Error{code: :invalid_provider_result}} =
             Jido.Chat.execute(client(), command(client()),
               options: [observer: self(), response: {:ok, %{"wrong" => true}}]
             )

    assert_receive {:invoked, _, _}

    request =
      Signal.DeleteMessage.new!(%{
        "client_id" => "test",
        "request_id" => "r",
        "room_id" => "room-1",
        "message_id" => "message-1"
      })

    assert {:error, %Jido.Chat.Error{code: :unsupported, signal: signal}} =
             Jido.Chat.execute(client(), request, options: [observer: self()])

    assert signal.data["outcome"] == "not_attempted"
    refute_receive {:invoked, _, _}
  end

  test "the complete operation API uses native Actions and exact Signal definitions" do
    assert length(Jido.Chat.actions()) == 23
    assert length(Jido.Chat.signal_definitions()) == 86

    for {definition, action} <- Jido.Chat.operations() do
      assert action.signal_definition() == definition
      assert Jido.ChatAction in List.flatten(Keyword.get_values(action.__info__(:attributes), :behaviour))

      assert action.signal_definitions() == [
               definition,
               Module.concat(action, Completed),
               Module.concat(action, Failed)
             ]

      {_, operation, _, _, _} = Jido.Chat.Operations.Definitions.lookup(definition.type())
      signal = Jido.Chat.AdapterTestKit.Factories.operation_request(client(), operation)
      assert {:ok, _} = action.validate_params(signal.data)
      assert action.name() != ""
      assert {:ok, _} = Jason.encode(action.authoring_contract())
      assert {:error, _} = action.validate_params(%{signal: %{}})
      assert {:error, _} = action.validate_output(%{signal: %{}})
    end
  end

  test "retired stateful APIs and unused adapter helpers are removed" do
    for mod <- [
          Jido.Chat.Binding,
          Jido.Chat.Resources,
          Jido.Chat.RequestStore,
          Jido.Chat.Handlers,
          Jido.Chat.Operation,
          Jido.Chat.Adapters.Mentions,
          Jido.Chat.Adapters.Threading,
          Jido.Chat.CapabilityMatrix,
          Jido.Chat.ChannelMeta,
          Jido.Chat.ChannelRef,
          Jido.Chat.FetchOptions,
          Jido.Chat.Errors.Ingress
        ] do
      refute Code.ensure_loaded?(mod)
    end

    refute function_exported?(Jido.Chat, :bind, 2)
    refute function_exported?(Jido.Chat, :put_resource, 3)
  end

  defp owned_tables do
    :ets.all() |> Enum.filter(&(:ets.info(&1, :owner) == self())) |> MapSet.new()
  end
end
