defmodule Jido.Chat.Telegram.ActionsContractTest do
  use Covenant.Case, component: "jido_chat_telegram.actions", async: true
  @moduletag capture_log: true
  alias Jido.Chat
  alias Jido.Chat.Telegram
  alias Jido.Chat.Telegram.ContractFixtures, as: F

  @tag obligation: "jido_chat_telegram.actions.I1"
  test "all fourteen Actions execute exact provider calls for two clients through Exec and Chat" do
    for id <- ["alpha", "beta"], row <- F.cases(), entry <- [:exec, :chat] do
      client = F.client(id)
      before = client
      action = F.module(row["action"])
      request = F.request(action, client)
      options = [local_setting: "private-transport-option"]

      result =
        case entry do
          :exec ->
            assert {:ok, %{signal: signal}} =
                     Jido.Chat.Telegram.ActionHelpers.execute(action, request, %{client: client, options: options},
                       max_attempts: 1
                     )

            signal

          :chat ->
            assert {:ok, signal} = Chat.execute(client, request, options: options)
            signal
        end

      F.completed(action, client, request, result)
      assert_receive {:telegram_contract_wire, token, method, payload, private, _}
      assert token == "fixture-token:" <> id
      assert method == row["method"]
      assert payload == F.scope(row["payload"], client)
      assert private[:local_setting] == "private-transport-option"
      assert private[:observer] == self()
      refute Keyword.has_key?(private, :token)
      refute Keyword.has_key?(private, :secret_token)
      assert client == before

      expected = F.scope(row["result"], client)

      if action == Telegram.FetchUpdates do
        assert is_binary(result.data["result"]["delivery_id"])
        assert Map.delete(result.data["result"], "delivery_id") == Map.delete(expected, "delivery_id")
      else
        assert result.data["result"] == expected
      end
    end

    refute_receive {:telegram_contract_wire, _, _, _, _, _}
  end

  @tag obligation: "jido_chat_telegram.actions.I2"
  test "forged requests, foreign references, missing credentials, and legacy options make no provider call" do
    client = F.client()

    for row <- F.cases() do
      action = F.module(row["action"])
      request = F.request(action, client)

      for bad <- [
            %{request | type: "jido.chat.telegram.command.unknown"},
            %{request | dataschema: "urn:contract:unknown"},
            %{request | data: Map.put(request.data, "client_id", "foreign")},
            %{request | data: Map.put(request.data, "credentials", %{"token" => "never-project-this"})},
            %{request | data: Map.put(request.data, "request_id", self())},
            %{request | subject: "foreign-conversation"}
          ] do
        assert {:error, _} = Jido.Chat.Telegram.ActionHelpers.execute(action, bad, %{client: client}, max_attempts: 1)
      end
    end

    request = F.request(Telegram.SendDocument, client)

    for source <- [
          %{"client_id" => "foreign", "kind" => "media", "id" => "file"},
          %{"content_base64" => "invalid base64", "filename" => "report.txt"}
        ] do
      bad = %{request | data: Map.put(request.data, "source", source)}

      assert {:error, _} =
               Jido.Chat.Telegram.ActionHelpers.execute(Telegram.SendDocument, bad, %{client: client}, max_attempts: 1)
    end

    for invalid <- [
          %{client | credentials: %{}},
          %{client | credentials: %{token: ""}},
          %{client | adapter: UnknownAdapter}
        ] do
      assert {:error, _} = F.run(Telegram.GetMe, invalid)
    end

    request = F.request(Telegram.GetMe, client)
    assert {:error, _} = Jido.Chat.Telegram.ActionHelpers.execute(Telegram.GetMe, request, %{}, max_attempts: 1)

    for key <- [:reply_markup, :parse_mode, :format, :thread_id, :reply_to_id, :fallback_to_dm] do
      assert {:error, %Chat.Error{signal: failed}} = F.run(Telegram.GetMe, client, %{}, [{key, "legacy"}])
      assert failed.data["outcome"] == "not_attempted"
    end

    refute_receive {:telegram_contract_wire, _, _, _, _, _}
  end

  @tag obligation: "jido_chat_telegram.actions.I3"
  test "Telegram status failures expose safe categories and hints without raw details or retries" do
    client = F.client()
    request = F.request(Telegram.GetMe, client)

    for {status, code} <- [
          {401, :unauthorized},
          {403, :forbidden},
          {404, :not_found},
          {429, :rate_limited},
          {400, :provider_failure}
        ],
        retry_after <- [0, 3, -1, "3"] do
      body =
        Jason.encode!(%{
          "error_code" => status,
          "description" => "never-project-this",
          "parameters" => %{"retry_after" => retry_after}
        })

      response = {:error, %ExGram.Error{code: :response_status_not_match, message: body}}

      assert {:error, %Chat.Error{code: ^code, signal: failed}} =
               Chat.execute(client, request, options: [contract_response: response])

      assert failed.type == Telegram.GetMe.Failed.type()
      assert failed.data["outcome"] == "rejected"
      assert failed.data["code"] == Atom.to_string(code)
      assert failed.data["operation"] == request.type
      assert failed.data["client_id"] == client.id
      assert failed.data["request_id"] == request.data["request_id"]
      assert failed.extensions["traceparent"] == F.trace()
      assert failed.extensions["jidocausationid"] == request.id

      if is_integer(retry_after) and retry_after >= 0,
        do: assert(failed.data["retry_after_ms"] == retry_after * 1000),
        else: refute(Map.has_key?(failed.data, "retry_after_ms"))

      assert F.round_trip(failed) == failed
      assert_receive {:telegram_contract_wire, _, "getMe", %{}, _, _}
    end

    for response <- [
          {:error, "https://api.telegram.org/botfixture-token:alpha/never-project-this"},
          {:error, %ExGram.Error{code: :response_status_not_match, message: "invalid JSON"}},
          {:error, %ExGram.Error{code: :response_status_not_match, message: ~s({"error_code":503})}},
          :raise,
          :throw
        ] do
      assert {:error, %Chat.Error{signal: failed}} =
               Chat.execute(client, request, options: [contract_response: response])

      assert failed.data["outcome"] == "unknown"
      assert F.round_trip(failed) == failed
      assert_receive {:telegram_contract_wire, _, "getMe", %{}, _, _}
    end

    refute_receive {:telegram_contract_wire, _, _, _, _, _}
  end

  @tag obligation: "jido_chat_telegram.actions.I3"
  test "every Action rejects malformed provider success and a deadline makes one attempt" do
    client = F.client()

    for row <- F.cases() do
      action = F.module(row["action"])

      assert {:error, %Chat.Error{code: :invalid_provider_result, signal: failed}} =
               F.run(action, client, %{}, contract_response: {:ok, nil})

      assert failed.type == Module.concat(action, Failed).type()
      assert failed.data["outcome"] == "unknown"
      assert F.round_trip(failed) == failed
      assert_receive {:telegram_contract_wire, _, _, _, _, _}
    end

    request = F.request(Telegram.GetMe, client)

    assert {:error, %Chat.Error{code: :timeout, signal: failed}} =
             Chat.execute(client, request, timeout: 100, options: [contract_response: :block])

    assert_receive {:telegram_contract_wire, _, "getMe", %{}, _, task}
    assert failed.type == Telegram.GetMe.Failed.type()
    assert failed.data["outcome"] == "unknown"
    assert failed.extensions["jidocausationid"] == request.id
    assert F.round_trip(failed) == failed
    refute Process.alive?(task)
    refute_receive {:telegram_contract_wire, _, _, _, _, _}
  end

  @tag obligation: "jido_chat_telegram.actions.I4"
  test "explicit draft Actions write once and webhook secrets stay in private context" do
    client = F.client()

    for {format, method} <- [
          {"plain", "sendMessageDraft"},
          {"markdown", "sendRichMessageDraft"},
          {"html", "sendRichMessageDraft"}
        ] do
      assert {:ok, %{signal: completed}} = F.run(Telegram.SendDraft, client, %{"format" => format})
      assert completed.data["result"] == %{"acknowledged" => true, "draft_id" => 7}
      assert_receive {:telegram_contract_wire, _, ^method, %{"chat_id" => 123, "draft_id" => 7}, _, _}
      assert F.round_trip(completed) == completed
      refute_receive {:telegram_contract_wire, _, _, _, _, _}
    end

    for action <- [Telegram.SetWebhook, Telegram.GetWebhookInfo, Telegram.DeleteWebhook] do
      assert {:ok, %{signal: completed}} = F.run(action, client)
      assert_receive {:telegram_contract_wire, _, method, payload, _, _}
      assert method == F.provider_case(action)["method"]

      if action == Telegram.SetWebhook,
        do: assert(payload["secret_token"] == "fixture-secret:alpha"),
        else: refute(Map.has_key?(payload, "secret_token"))

      assert F.round_trip(completed) == completed
    end

    refute_receive {:telegram_contract_wire, _, _, _, _, _}
  end

  @tag obligation: "jido_chat_telegram.actions.I4"
  test "webhook verification is pure and requires the configured exact secret" do
    for id <- ["alpha", "beta"] do
      client = F.client(id)
      assert :ok = Telegram.Webhook.verify(client, [{"X-Telegram-Bot-Api-Secret-Token", "fixture-secret:" <> id}])
      assert {:error, :invalid_webhook_secret} = Telegram.Webhook.verify(client, %{})

      assert {:error, :invalid_webhook_secret} =
               Telegram.Webhook.verify(client, %{"x-telegram-bot-api-secret-token" => "wrong"})

      assert {:error, :missing_webhook_secret} = Telegram.Webhook.verify(%{client | credentials: %{}}, %{})
    end

    refute_receive {:telegram_contract_wire, _, _, _, _, _}
  end

  @tag obligation: "jido_chat_telegram.actions.I5"
  test "mixed Flow and typed Router Instruction Dispatch compose with provider Signals" do
    client = F.client()
    message = F.request(Chat.SendMessage, client, %{"room_id" => "123", "text" => "Choose"})
    poll = F.request(Telegram.SendPoll, client)

    assert {:ok, %{message: message_result, poll: poll_result}} =
             Jido.Exec.run(F.MixedFlow, %{message: message.data, poll: poll.data}, %{client: client}, max_attempts: 1)

    assert_receive {:telegram_contract_wire, _, first_method, _, _, _}
    assert first_method == "sendMessage"
    assert_receive {:telegram_contract_wire, _, second_method, _, _, _}
    assert second_method == "sendPoll"
    assert {:ok, message_result} = Chat.SendMessage.reply(message, message_result, source: client.source)
    assert {:ok, poll_result} = Telegram.SendPoll.reply(poll, poll_result, source: client.source)
    assert message_result.extensions["jidocausationid"] == message.id
    assert poll_result.extensions["jidocausationid"] == poll.id
    assert F.round_trip(poll_result) == poll_result

    router =
      Jido.Signal.Router.new!([{Telegram.Signal.SendPoll, Jido.Instruction.template(:action, Telegram.SendPoll)}])

    assert {:ok, [template]} = Jido.Signal.Router.route(router, poll)
    assert {:ok, instruction} = Jido.Instruction.bind(template, poll.data, %{client: client, signal: poll})
    assert {:ok, data} = Jido.Exec.run(instruction)
    assert {:ok, completed} = Telegram.SendPoll.reply(poll, data, source: client.source)
    assert_receive {:telegram_contract_wire, _, "sendPoll", _, _, _}
    assert :ok = Jido.Signal.Dispatch.dispatch(completed, {:pid, [target: self()]})
    assert_receive {:signal, ^completed}
    assert F.round_trip(completed) == completed
    refute_receive {:telegram_contract_wire, _, _, _, _, _}
  end

  @tag obligation: "jido_chat_telegram.actions.I5"
  test "a failed mixed Flow dependency prevents the provider Action write" do
    client = F.client()
    message = F.request(Chat.SendMessage, client, %{"room_id" => "123", "text" => "Choose"})
    poll = F.request(Telegram.SendPoll, client)

    assert {:error, _} =
             Jido.Exec.run(
               F.MixedFlow,
               %{message: message.data, poll: poll.data},
               %{client: client, options: [contract_response: {:error, {:rejected, :forbidden}}]},
               max_attempts: 1
             )

    assert_receive {:telegram_contract_wire, _, "sendMessage", _, _, _}
    refute_receive {:telegram_contract_wire, _, _, _, _, _}
  end

  @tag obligation: "jido_chat_telegram.actions.I6"
  test "every Action schema matches its Signal data and validates serialized data" do
    client = F.client()

    for row <- F.cases() do
      action = F.module(row["action"])
      definition = action.signal_definition()
      request = F.request(action, client)
      json = action.authoring_contract()
      assert json["input_schema"] == F.entry(definition)["data_schema"]
      assert json["output_schema"] == F.entry(Module.concat(action, Completed))["data_schema"]
      assert action.schema() == definition.schema()
      assert action.output_schema() == Module.concat(action, Completed).schema()
      data = request.data |> Jason.encode!() |> Jason.decode!()

      assert {:ok, completed} =
               Jido.Exec.run(action, data, %{client: client, signal: request}, max_attempts: 1)

      assert completed["operation"] == request.type
      assert {:ok, reply} = action.reply(request, completed, source: client.source)
      assert F.round_trip(reply) == reply
      assert_receive {:telegram_contract_wire, _, _, _, _, _}

      for bad <- [
            Map.put(data, "token", "never-project-this"),
            Map.put(data, "request_id", 42),
            %{"signal" => Jido.Signal.Codec.to_map(request)}
          ] do
        assert {:error, _} = Jido.Exec.run(action, bad, %{client: client, signal: request}, max_attempts: 1)
      end
    end

    refute_receive {:telegram_contract_wire, _, _, _, _, _}
  end
end
