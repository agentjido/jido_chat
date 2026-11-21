defmodule Jido.Chat.Telegram.APIHardeningTest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true
  alias Jido.Chat
  alias Jido.Chat.Telegram

  defmodule Transport do
    def call(_token, method, payload, opts) do
      send(opts[:observer], {:wire, method, payload})
      opts[:response]
    end
  end

  defp client do
    Chat.Client.new!(Telegram.Adapter,
      id: "telegram",
      credentials: %{token: "private-token"},
      config: [observer: self()],
      transport: Transport
    )
  end

  defp request(action, fields) do
    action.signal_definition().new!(Map.merge(%{"client_id" => "telegram", "request_id" => "r"}, fields))
  end

  defp execute(action, fields, response) do
    Chat.execute(client(), request(action, fields), options: [response: response])
  end

  defp topic_update(kind, payload, thread \\ 7) do
    %{
      "update_id" => 42,
      "message" => %{
        "message_id" => 5,
        "message_thread_id" => thread,
        "chat" => %{"id" => -100_123, "type" => "supergroup"},
        "from" => %{"id" => 123},
        kind => payload
      }
    }
  end

  test "pulling an update batch and webhook normalization produce the same facts" do
    updates = [topic_update("forum_topic_created", %{"name" => "Support"})]
    assert {:ok, completed} = execute(Telegram.FetchUpdates, %{"offset" => 40, "timeout" => 0}, {:ok, updates})
    assert_receive {:wire, "getUpdates", %{"offset" => 40, "timeout" => 0}}
    result = completed.data["result"]
    assert result["next_offset"] == 43
    assert {:ok, webhook} = Chat.normalize(client(), updates)
    [wire] = result["signals"]
    assert {:ok, pulled} = Jido.Signal.Catalog.decode(Chat.catalog(client()), wire)
    [pushed] = webhook.signals
    assert pulled.type == Chat.Signal.ThreadStarted.type()
    assert {pulled.data, pulled.source, pulled.subject} == {pushed.data, pushed.source, pushed.subject}
    assert pulled.data["delivery_id"] == webhook.id
    assert {:ok, empty} = execute(Telegram.FetchUpdates, %{"offset" => 43}, {:ok, []})
    assert empty.data["result"]["next_offset"] == 43
    assert empty.data["result"]["signals"] == []
    assert_receive {:wire, "getUpdates", %{"offset" => 43}}
    refute_receive {:wire, _, _}
  end

  test "topic changes become explicit facts and malformed topics become normalization failures" do
    cases = [
      {"forum_topic_edited", %{"name" => "Renamed"}, "updated", "7"},
      {"forum_topic_closed", %{}, "closed", "7"},
      {"forum_topic_reopened", %{}, "reopened", "7"},
      {"general_forum_topic_hidden", %{}, "closed", "1"},
      {"general_forum_topic_unhidden", %{}, "reopened", "1"}
    ]

    for {kind, payload, change, id} <- cases do
      thread = if id == "1", do: nil, else: 7
      assert {:ok, delivery} = Chat.normalize(client(), topic_update(kind, payload, thread))
      assert [signal] = delivery.signals
      assert signal.type == Chat.Signal.ThreadChanged.type()
      assert signal.data["thread_id"] == id
      assert signal.data["change"] == change
      assert signal.data["actor_id"] == "123"
    end

    assert {:ok, delivery} = Chat.normalize(client(), topic_update("forum_topic_created", %{}, nil))
    assert [failed] = delivery.signals
    assert failed.type == Chat.Signal.NormalizationFailed.type()
    assert Chat.Signal.ThreadChanged in Chat.event_definitions(client())
    refute Chat.Signal.ModalSubmitted in Chat.event_definitions(client())
  end

  test "provider errors expose safe categories and rate-limit duration without raw details" do
    for {status, code} <- [
          {401, :unauthorized},
          {403, :forbidden},
          {404, :not_found},
          {429, :rate_limited},
          {400, :provider_failure}
        ] do
      body =
        Jason.encode!(%{
          "error_code" => status,
          "description" => "private-token private provider details",
          "parameters" => %{"retry_after" => 3}
        })

      response = {:error, %ExGram.Error{code: :response_status_not_match, message: body}}
      assert {:error, %Chat.Error{code: ^code, signal: failed}} = execute(Telegram.GetMe, %{}, response)
      assert failed.data["outcome"] == "rejected"
      assert failed.data["retry_after_ms"] == 3000
      assert_receive {:wire, "getMe", %{}}
      {:ok, wire} = Jido.Signal.Codec.serialize(failed)
      refute wire =~ "private"
      assert {:ok, ^failed} = Jido.Signal.Catalog.decode(Telegram.catalog(), wire)
    end

    for body <- ["invalid JSON", "{}", Jason.encode!(%{"error_code" => 503})] do
      response = {:error, %ExGram.Error{code: :response_status_not_match, message: body}}
      assert {:error, %Chat.Error{signal: failed}} = execute(Telegram.GetMe, %{}, response)
      assert failed.data["outcome"] == "unknown"
      refute Map.has_key?(failed.data, "retry_after_ms")
      assert_receive {:wire, "getMe", %{}}
    end
  end

  test "OpenDm verifies an existing private destination and rejects other rooms" do
    assert {:ok, result} = execute(Chat.OpenDm, %{"user_id" => "123"}, {:ok, %{"id" => 123, "type" => "private"}})
    assert result.data["result"] == %{"id" => "123", "kind" => "direct"}
    assert_receive {:wire, "getChat", %{"chat_id" => "123"}}

    for room <- [%{"id" => 123, "type" => "group"}, %{"id" => 456, "type" => "private"}] do
      assert {:error, %Chat.Error{code: :not_found}} = execute(Chat.OpenDm, %{"user_id" => "123"}, {:ok, room})
      assert_receive {:wire, "getChat", _}
    end

    refute_receive {:wire, _, _}
  end

  test "stream failures retain rate-limit hints and stop before a second source read" do
    observer = self()

    source =
      Stream.map(["first", "second"], fn chunk ->
        send(observer, {:read, chunk})
        chunk
      end)

    error = %ExGram.Error{
      code: :response_status_not_match,
      message: Jason.encode!(%{"error_code" => 429, "parameters" => %{"retry_after" => 2}})
    }

    assert {:error, %Chat.Error{code: :rate_limited, signal: failed}} =
             Chat.stream_text(client(), "123", source, options: [response: {:error, error}])

    assert failed.data["retry_after_ms"] == 2000
    assert failed.data["outcome"] == "unknown"
    assert_receive {:read, "first"}
    refute_receive {:read, "second"}
    assert_receive {:wire, "sendMessageDraft", _}
    refute_receive {:wire, _, _}
  end

  test "provider discovery, query types, and agent schemas use the core interface" do
    assert length(Chat.operations(client())) == 37
    assert length(Chat.actions(client())) == 37

    for {definition, action} <- Telegram.operations() do
      assert {definition, action} in Chat.operations(client())
      schema = action.authoring_contract()["input_schema"]
      assert action.type() == definition.type()
      assert action.schema() == definition.schema()
      assert schema["type"] == "object"
      assert "request_id" in schema["required"]
    end

    assert Telegram.Signal.GetWebhookInfo.type() == "jido.chat.telegram.query.get_webhook_info"
    refute function_exported?(Telegram, :command_routes, 0)
  end
end
