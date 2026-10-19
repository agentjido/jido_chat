defmodule Jido.Chat.APIBoundaryTest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true
  alias Jido.Chat.{Client, AdapterTestKit}
  alias AdapterTestKit.{Assertions, Factories}

  defmodule Adapter do
    use Jido.Chat.Adapter
    def capabilities, do: %{send_message: :native, create_thread: :native}
    def normalize(_, _, _), do: {:error, :unused}

    def invoke(_, request, opts) do
      send(opts[:observer], {:provider, request})

      case request.type do
        "jido.chat.command.create_thread" ->
          {:ok, %{"id" => "topic-1", "room_id" => request.data["room_id"], "name" => request.data["name"]}}

        _ ->
          {:ok, %{"id" => "m", "room_id" => request.data["room_id"]}}
      end
    end
  end

  defp client, do: Client.new!(Adapter, id: "sdk")

  test "CreateThread creates by name and existing threads are addressed through SendMessage" do
    request = Factories.operation_request(client(), :create_thread, %{"name" => "Support"})
    created = Assertions.assert_operation_success(Jido.Chat.execute(client(), request, options: [observer: self()]))
    assert created.type == Jido.Chat.CreateThread.Completed.type()
    assert created.data["result"]["name"] == "Support"
    assert_receive {:provider, ^request}
    send_request = Factories.operation_request(client(), :send_message, %{"thread_id" => created.data["result"]["id"]})
    Assertions.assert_operation_success(Jido.Chat.execute(client(), send_request, options: [observer: self()]))
    assert_receive {:provider, ^send_request}
  end

  test "removed fields and missing thread identities fail before provider I/O" do
    cases = [
      {:create_thread, "message_id", "m"},
      {:create_thread, "topic_name", "Support"},
      {:fetch_messages, "reply_to_id", "m"},
      {:fetch_messages, "format", "html"},
      {:fetch_thread, "format", "html"},
      {:get_user, "thread_id", "t"},
      {:download_file, "media_ref", %{}},
      {:edit_message, "reply_to_id", "m"},
      {:edit_message, "thread_id", "t"},
      {:post_ephemeral, "fallback_to_dm", true}
    ]

    for {operation, key, value} <- cases do
      valid = Factories.operation_request(client(), operation)
      invalid = %{valid | data: Map.put(valid.data, key, value)}
      assert {:error, _} = Jido.Chat.execute(client(), invalid, options: [observer: self()])
    end

    for operation <- [:fetch_thread, :get_thread_participants] do
      valid = Factories.operation_request(client(), operation)

      assert {:error, _} =
               Jido.Chat.execute(client(), %{valid | data: Map.delete(valid.data, "thread_id")},
                 options: [observer: self()]
               )
    end

    refute_receive {:provider, _}
  end

  test "all core result types belong to exactly one Action and reject another operation" do
    for {definition, action} <- Jido.Chat.operations() do
      [^definition, completed, failed] = action.signal_definitions()
      assert completed == Module.concat(action, Completed)
      assert failed == Module.concat(action, Failed)
      assert completed.type() == definition.type() <> ".completed"
      assert failed.type() == definition.type() <> ".failed"
      assert failed.dataschema() == definition.dataschema() <> ":failed"

      data = %{
        "client_id" => "sdk",
        "request_id" => "r",
        "operation" => "wrong",
        "code" => "unsupported",
        "outcome" => "not_attempted"
      }

      assert {:error, _} = failed.new(data)
    end

    types = Enum.map(Jido.Chat.signal_definitions(), & &1.type())
    assert length(types) == length(Enum.uniq(types))
  end

  test "test kit validates success, failure, and JSON against the supplied catalog" do
    request = Factories.operation_request(client(), :send_message)
    result = Jido.Chat.execute(client(), request, options: [observer: self()])
    signal = Assertions.assert_operation_success(result)
    assert Assertions.assert_operation_success({:ok, %{signal: signal}}, Jido.Chat.catalog()) == signal
    assert :ok = Assertions.assert_json_round_trip(signal)
    assert_receive {:provider, _}
    unsupported = Factories.operation_request(client(), :delete_message)
    error = Jido.Chat.execute(client(), unsupported, options: [observer: self()])
    failed = Assertions.assert_operation_failure(error)
    assert failed.type == Jido.Chat.DeleteMessage.Failed.type()
    assert Assertions.assert_operation_failure(error, Jido.Chat.catalog()) == failed
    assert :ok = Assertions.assert_json_round_trip(failed, Jido.Chat.catalog())
    assert_raise ExUnit.AssertionError, fn -> Assertions.assert_operation_success(error) end
    assert_raise ExUnit.AssertionError, fn -> Assertions.assert_operation_failure(result) end

    assert_raise ExUnit.AssertionError, fn ->
      Assertions.assert_operation_success(result, Jido.Signal.Catalog.new!([]))
    end

    refute_receive {:provider, _}
  end

  test "duplicate and renamed Actions and generic result definitions are removed" do
    for module <- [
          Jido.Chat.PostMessage,
          Jido.Chat.PostChannelMessage,
          Jido.Chat.FetchChannelMessages,
          Jido.Chat.Stream,
          Jido.Chat.OpenThread,
          Jido.Chat.FetchMedia,
          Jido.Chat.Signal.OperationCompleted,
          Jido.Chat.Signal.OperationFailed
        ] do
      refute Code.ensure_loaded?(module)
    end
  end
end
