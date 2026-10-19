defmodule Jido.Chat.OperationAdapterTest do
  alias Jido.Chat.AdapterTestKit.{Assertions, Factories}
  alias Jido.Chat.{Client, Signal}

  defmodule WireAdapter do
    use Jido.Chat.Adapter
    def capabilities, do: Map.new(Jido.Chat.Operations.Definitions.all(), fn {_, {_, op, _, _, _}} -> {op, :native} end)
    def default_transport, do: __MODULE__

    def invoke(client, request, opts) do
      {_, operation, _, _, _} = Jido.Chat.Operations.Definitions.lookup(request.type)
      send(opts[:observer], {:provider, operation, request, client})

      case opts[:provider_return] do
        :raise -> raise "private provider error"
        :throw -> throw("private provider error")
        value -> value
      end
    end

    def normalize(_client, input, _opts), do: input
  end

  use Jido.Chat.AdapterTestKit, adapter: WireAdapter
  @moduletag capture_log: true

  defp client, do: Client.new!(WireAdapter, id: "wire", credentials: %{token: "private"})

  defp raw_message do
    %{
      "id" => "123",
      "room_id" => "room/1",
      "text" => "hello",
      "sender" => %{"id" => "u", "display_name" => "Ada"},
      "timestamp" => "2026-10-17T12:00:00Z",
      "status" => "updated",
      "role" => "user",
      "media" => [
        %{
          "kind" => "image",
          "resource_ref" => %{"id" => "photo-1", "client_id" => "wire", "kind" => "media"},
          "name" => "photo.png"
        }
      ]
    }
  end

  defp provider_return(:message), do: {:ok, raw_message()}
  defp provider_return(:acknowledgement), do: {:ok, %{"acknowledged" => true}}

  defp provider_return(:conversation),
    do: {:ok, %{"id" => "room/1", "kind" => "group", "name" => "Room", "topic" => "Topic"}}

  defp provider_return(:thread),
    do: {:ok, %{"id" => "t", "room_id" => "room/1", "parent_message_id" => "m", "name" => "Thread"}}

  defp provider_return(:created_thread), do: provider_return(:thread)

  defp provider_return(:user), do: {:ok, %{"id" => "u", "username" => "ada", "is_bot" => false}}

  defp provider_return(:subject),
    do: {:ok, %{"id" => "t", "kind" => "thread", "room_id" => "room/1", "title" => "Thread"}}

  defp provider_return(:participants),
    do: {:ok, %{"participants" => [%{"id" => "u"}], "complete" => true, "scope" => "all"}}

  defp provider_return(:resource), do: {:ok, %{"content_base64" => Base.encode64(<<0, 255, 1>>)}}
  defp provider_return(:modal), do: {:ok, %{"opened" => true, "id" => "v"}}
  defp provider_return(:options), do: {:ok, %{"options" => [%{"label" => "One", "value" => "1"}], "complete" => true}}
  defp provider_return(:message_page), do: {:ok, %{"messages" => [raw_message()], "complete" => true}}

  defp provider_return(:thread_page),
    do: {:ok, %{"threads" => [%{"id" => "t", "room_id" => "room/1"}], "next_cursor" => "next", "complete" => false}}

  for {_, {definition, operation, _, shape, _}} <- Jido.Chat.Operations.Definitions.all() do
    test "#{operation} receives its full request Signal and returns a typed result Signal" do
      client = client()
      request = Factories.operation_request(client, unquote(operation))
      response = provider_return(unquote(shape))

      result =
        Assertions.assert_operation_success(
          Jido.Chat.execute(client, request, options: [observer: self(), provider_return: response, stream: ["hello"]])
        )

      assert result.type == unquote(definition).type() <> ".completed"
      assert result.data["operation"] == unquote(definition).type()
      assert result.data["request_id"] == request.data["request_id"]
      assert_receive {:provider, unquote(operation), ^request, ^client}
      Assertions.assert_json_round_trip(result)
      assert is_map(Zoi.to_json_schema(unquote(definition).schema()))
    end
  end

  test "routing data is carried by the Signal, not copied into private options" do
    client = client()

    request =
      Factories.operation_request(client, :send_message, %{
        "thread_id" => "new",
        "reply_to_id" => "reply",
        "format" => "plain"
      })

    assert {:ok, _} =
             Jido.Chat.execute(client, request, options: [observer: self(), provider_return: provider_return(:message)])

    assert_receive {:provider, :send_message, ^request, ^client}
  end

  test "errors, exceptions, and throws produce safe failure Signals without retries" do
    for response <- [
          :raise,
          :throw,
          {:error, :unsupported},
          {:error, {:rejected, "private"}},
          {:error, {:not_attempted, "private"}},
          {:ok, false}
        ] do
      request = Factories.operation_request(client(), :send_message)

      assert {:error, %Jido.Chat.Error{signal: failed} = error} =
               Jido.Chat.execute(client(), request, options: [observer: self(), provider_return: response])

      assert_receive {:provider, :send_message, _, _}
      refute_receive {:provider, _, _, _}
      refute inspect(failed) =~ "private"
      assert Exception.message(error) =~ "Chat operation failed"
      if response == {:error, :unsupported}, do: assert(failed.data["outcome"] == "unknown")
    end
  end

  test "a provider cannot change the requested room in a successful result" do
    request = Factories.operation_request(client(), :send_message)

    assert {:error, %Jido.Chat.Error{code: :invalid_provider_result}} =
             Jido.Chat.execute(client(), request,
               options: [observer: self(), provider_return: {:ok, %{"id" => "m", "room_id" => "other"}}]
             )
  end

  test "invalid clients, private input, and foreign references fail before provider I/O" do
    for opts <- [
          [id: ""],
          [id: "a", id: "b"],
          [id: "a", credentials: :bad],
          [id: "a", config: :bad],
          [id: "a", transport: 42],
          [id: "a", unknown: true]
        ] do
      assert {:error, _} = Client.new(WireAdapter, opts)
    end

    assert_raise Jido.Chat.Errors.Contract, fn -> Client.new!(WireAdapter, id: "") end
    assert {:error, _} = Client.new(:does_not_exist, id: "bad")
    assert {:error, _} = Jido.Chat.execute(nil, nil)
    assert {:error, _} = Jido.Chat.send_message(nil, nil)
    assert {:error, _} = Jido.Chat.normalize(nil, nil)

    for input <- [{:error, "private payload"}, {:ok, %{}}, :raise] do
      assert {:error, %Jido.Chat.Errors.Contract{}} = Jido.Chat.normalize(client(), input)
    end

    request =
      Factories.operation_request(client(), :download_file, %{
        "resource_ref" => %{"id" => "photo-1", "client_id" => "other", "kind" => "media"}
      })

    assert {:error, _} = Jido.Chat.execute(client(), request, options: [observer: self()])
    refute_receive {:provider, _, _, _}
  end

  test "the test kit builds only values and validates complete deliveries" do
    client = client()
    fact = Factories.message_received(client)
    assert {:ok, delivery} = Jido.Chat.Delivery.new(client, "delivery-1", [fact])
    assert Assertions.assert_delivery(client, {:ok, delivery}) == delivery
    assert Jido.Chat.AdapterTestKit.supported?(WireAdapter, :send_message)

    assert Factories.request(Signal.SendMessage, %{
             "client_id" => client.id,
             "request_id" => "r",
             "room_id" => "room/1",
             "text" => "hello"
           }).type == Signal.SendMessage.type()
  end
end
