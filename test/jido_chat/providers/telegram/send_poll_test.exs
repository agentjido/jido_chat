defmodule Jido.Chat.Telegram.SendPollTest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true
  alias Jido.Chat.Client
  alias Jido.Chat.Telegram.{Adapter, SendPoll}

  defmodule Transport do
    def call(token, "sendPoll", payload, opts) do
      send(opts[:observer], {:poll, token, payload})

      case opts[:response] do
        nil -> {:ok, %{message_id: 42, chat: %{id: payload["chat_id"]}, poll: %{id: "poll-1"}}}
        response -> response
      end
    end
  end

  defmodule PollFlow do
    use Jido.Flow, name: "telegram_poll_flow"

    flow do
      step("poll", action: SendPoll, params: input(:signal))
      output(result("poll"))
    end
  end

  defp client,
    do: Client.new!(Adapter, id: "telegram", credentials: %{token: "private-token"}, transport: Transport)

  defp request do
    Jido.Chat.Signal.Policy.new!(Jido.Chat.Telegram.Signal.SendPoll, %{
      "client_id" => "telegram",
      "request_id" => "poll-request-1",
      "room_id" => "123",
      "question" => "Ship today?",
      "options" => ["Yes", "No"],
      "thread_id" => "7",
      "is_anonymous" => false
    })
  end

  test "a real provider extension runs as a native Action and composes in a Flow" do
    assert is_nil(Jido.Chat.Operations.Definitions.lookup(request().type))
    assert length(Jido.Chat.actions()) == 23

    for action <- [SendPoll, PollFlow] do
      request = request()
      params = if action == SendPoll, do: request.data, else: %{signal: request.data}

      assert {:ok, data} =
               Jido.Exec.run(action, params, %{client: client(), signal: request, options: [observer: self()]})

      assert {:ok, completed} = SendPoll.reply(request, data, source: client().source)

      assert_receive {:poll, "private-token",
                      %{
                        "chat_id" => "123",
                        "question" => "Ship today?",
                        "options" => [%{"text" => "Yes"}, %{"text" => "No"}],
                        "message_thread_id" => "7",
                        "is_anonymous" => false
                      }}

      assert completed.type == SendPoll.Completed.type()
      assert completed.data["result"] == %{"id" => "42", "room_id" => "123", "poll_id" => "poll-1"}
      catalog = Jido.Signal.Catalog.new!(Jido.Chat.signal_definitions() ++ SendPoll.signal_definitions())
      assert {:ok, json} = Jido.Signal.Codec.serialize(completed)
      assert {:ok, ^completed} = Jido.Signal.Catalog.decode(catalog, json)
      refute json =~ "private-token"
    end
  end

  test "a wrong request or client fails before the transport call" do
    command = request()

    for invalid <- [
          %{command | dataschema: "wrong"},
          %{command | data: Map.put(command.data, "client_id", "other")},
          %{command | data: Map.put(command.data, "options", ["one"])}
        ] do
      assert {:error, _} =
               Jido.Chat.Telegram.ActionHelpers.execute(SendPoll, invalid, %{
                 client: client(),
                 options: [observer: self()]
               })
    end

    assert {:error, %Jido.Chat.Error{signal: failed}} =
             Jido.Chat.Telegram.ActionHelpers.execute(SendPoll, command, %{client: %{client() | credentials: %{}}})

    assert failed.data["outcome"] == "not_attempted"
    refute_receive {:poll, _, _}
  end

  test "provider errors and invalid poll results return typed safe failure Signals" do
    for {response, code} <- [
          {{:error, "private-provider-body"}, :provider_failure},
          {{:ok, %{}}, :invalid_provider_result}
        ] do
      assert {:error, %Jido.Chat.Error{code: ^code, signal: failed}} =
               Jido.Chat.Telegram.ActionHelpers.execute(SendPoll, request(), %{
                 client: client(),
                 options: [observer: self(), response: response]
               })

      assert failed.type == SendPoll.Failed.type()
      assert failed.data["outcome"] == "unknown"
      assert_receive {:poll, _, _}
      refute inspect(failed) =~ "private"
    end

    refute_receive {:poll, _, _}
  end
end
