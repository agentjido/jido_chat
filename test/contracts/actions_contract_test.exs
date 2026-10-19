defmodule Jido.Chat.ActionsContractTest do
  use Covenant.Case, component: "jido_chat.actions", async: true
  @moduletag capture_log: true
  alias Jido.Chat
  alias Jido.Chat.ContractFixtures, as: F

  @tag obligation: "jido_chat.actions.I7"
  test "every core Action executes and validates a completion for two client identities" do
    assert Chat.operations() == F.pairs()
    assert Enum.sort(Chat.actions()) == F.pairs() |> Enum.map(&elem(&1, 1)) |> Enum.sort()

    for id <- ["alpha", "beta"], {_definition, action} <- F.pairs() do
      client = F.client(F.FirstAdapter, id)
      request = F.request(action, client)
      options = if action == Chat.StreamText, do: [stream: ["one", " two"]], else: []

      assert {:ok, %{signal: completed}} =
               F.execute(action, request, %{client: client, options: options}, max_attempts: 1)

      assert_receive {:contract_invoke, F.FirstAdapter, ^id, ^request, ^options, _}
      assert completed.type == Module.concat(action, Completed).type()
      assert completed.data["operation"] == request.type
      assert completed.data["client_id"] == id
      assert completed.data["request_id"] == request.data["request_id"]
      assert completed.source == client.source
      assert completed.extensions["traceparent"] == F.trace()
      assert completed.extensions["tracestate"] == "contract=fixture"
      assert completed.extensions["jidocausationid"] == request.id
      assert {:ok, _} = action.validate_output(completed.data)
      assert {:error, _} = action.validate_output(request.data)
      assert F.round_trip(completed) == completed
    end
  end

  @tag obligation: "jido_chat.actions.I2"
  test "foreign and malformed requests and context fail before provider execution" do
    client = F.client()
    request = F.request(Chat.SendMessage, client)

    invalid = [
      %{request | type: Chat.Signal.DeleteMessage.type()},
      %{request | dataschema: "urn:unknown:1"},
      %{request | subject: "foreign-room"},
      %{request | data: Map.put(request.data, "client_id", "beta")},
      %{request | data: Map.put(request.data, "text", self())},
      %{request | data: Map.put(request.data, "token", "private-token")},
      %{request | extensions: %{"traceparent" => "invalid"}},
      F.request(Chat.DeleteMessage, client),
      nil
    ]

    for bad <- invalid do
      assert {:error, _} = F.execute(Chat.SendMessage, bad, %{client: client}, max_attempts: 1)
    end

    assert {:error, _} = F.execute(Chat.SendMessage, request, %{}, max_attempts: 1)

    assert {:error, _} =
             F.execute(Chat.SendMessage, request, %{client: client, options: [:bad]}, max_attempts: 1)

    foreign =
      F.request(Chat.SendFile, client, %{"source" => %{"client_id" => "beta", "kind" => "file", "id" => "foreign"}})

    assert {:error, %Chat.Errors.Contract{}} = Chat.execute(client, foreign)
    refute_receive {:contract_invoke, _, _, _, _, _}
  end

  @tag obligation: "jido_chat.actions.I3"
  test "invalid or foreign provider results cannot produce success Signals" do
    client = F.client()

    invalid = [
      %{},
      %{"id" => 42, "room_id" => "room/1"},
      %{"id" => "m", "room_id" => "foreign"},
      %{"id" => "m", "room_id" => "room/1", "text" => self()},
      %{
        "id" => "m",
        "room_id" => "room/1",
        "media" => [%{"kind" => "file", "resource_ref" => %{"client_id" => "beta", "kind" => "media", "id" => "f"}}]
      },
      %{
        "id" => "m",
        "room_id" => "room/1",
        "media" => [
          %{
            "kind" => "file",
            "resource_ref" => %{"client_id" => client.id, "kind" => "media", "id" => "f"},
            "metadata" => %{"nested" => %{"token" => "private-token"}}
          }
        ]
      }
    ]

    for result <- invalid do
      assert {:error, %Chat.Error{code: :invalid_provider_result, signal: failed}} =
               Chat.send_text(client, "room/1", "Hello", options: [provider_return: {:ok, result}])

      assert_receive {:contract_invoke, _, _, _, _, _}
      assert failed.data["outcome"] == "unknown"
      assert failed.type == Chat.SendMessage.Failed.type()
      assert F.round_trip(failed) == failed
    end

    for {action, result} <- [
          {Chat.FetchMetadata, %{"id" => "room/1"}},
          {Chat.CreateThread, %{"id" => "topic", "room_id" => "room/1"}},
          {Chat.DownloadFile, %{"content_base64" => "invalid"}}
        ] do
      assert {:error, %Chat.Error{code: :invalid_provider_result}} =
               Chat.execute(client, F.request(action, client), options: [provider_return: {:ok, result}])

      assert_receive {:contract_invoke, _, _, _, _, _}
    end
  end

  @tag obligation: "jido_chat.actions.I4"
  test "provider failures expose only safe codes, outcomes, hints, and causal context" do
    client = F.client()
    request = F.request(Chat.SendMessage, client)

    cases =
      [
        {{:error, {:not_attempted, :unsupported}}, :unsupported, "not_attempted"},
        {{:error, {:not_attempted, :missing_token}}, :provider_failure, "not_attempted"},
        {{:error, {:rejected, "private provider details"}}, :provider_failure, "rejected"},
        {{:error, "private provider details"}, :provider_failure, "unknown"},
        {:raise, :provider_failure, "unknown"},
        {:throw, :provider_failure, "unknown"}
      ] ++
        for code <- [:unauthorized, :forbidden, :not_found, :rate_limited, :timeout],
            do:
              {{:error, {:rejected, code, %{retry_after_ms: 2000, raw: "private provider details"}}}, code, "rejected"}

    for {response, code, outcome} <- cases do
      assert {:error, %Chat.Error{code: ^code, signal: failed}} =
               Chat.execute(client, request, options: [provider_return: response])

      assert_receive {:contract_invoke, _, _, ^request, _, _}
      assert failed.type == Chat.SendMessage.Failed.type()
      assert failed.data["code"] == Atom.to_string(code)
      assert failed.data["outcome"] == outcome

      assert Map.take(failed.data, ["client_id", "request_id", "operation"]) == %{
               "client_id" => client.id,
               "request_id" => request.data["request_id"],
               "operation" => request.type
             }

      assert failed.extensions["traceparent"] == F.trace()
      assert failed.extensions["tracestate"] == "contract=fixture"
      assert failed.extensions["jidocausationid"] == request.id

      if code in [:unauthorized, :forbidden, :not_found, :rate_limited, :timeout],
        do: assert(failed.data["retry_after_ms"] == 2000)

      assert F.round_trip(failed) == failed
    end

    for hint <- [-1, "20", self()] do
      assert {:error, %Chat.Error{signal: failed}} =
               Chat.execute(client, request,
                 options: [provider_return: {:error, {:unknown, :unapproved_code, %{retry_after_ms: hint}}}]
               )

      assert failed.data["code"] == "provider_failure"
      assert failed.data["outcome"] == "unknown"
      refute Map.has_key?(failed.data, "retry_after_ms")
      assert_receive {:contract_invoke, _, _, _, _, _}
    end
  end

  @tag obligation: "jido_chat.actions.I5"
  test "native Flow, Router, Instruction, and Dispatch retain the Action boundary" do
    client = F.client()
    first = F.request(Chat.SendMessage, client, %{"request_id" => "first"})
    second = F.request(Chat.SendMessage, client, %{"request_id" => "second"})

    assert {:ok, %{first: first_result, second: second_result}} =
             Jido.Exec.run(F.ReplyFlow, %{first: first.data, second: second.data}, %{client: client}, max_attempts: 1)

    assert_receive {:contract_invoke, _, _, observed_first, _, _}
    assert observed_first.data == first.data
    assert_receive {:contract_invoke, _, _, observed_second, _, _}
    assert observed_second.data == second.data
    assert {:ok, first_reply} = Chat.SendMessage.reply(first, first_result, source: client.source)
    assert {:ok, second_reply} = Chat.SendMessage.reply(second, second_result, source: client.source)
    assert first_reply.extensions["jidocausationid"] == first.id
    assert second_reply.extensions["jidocausationid"] == second.id

    router = Jido.Signal.Router.new!([{Chat.Signal.SendMessage, Jido.Instruction.template(:action, Chat.SendMessage)}])
    assert {:ok, [template]} = Jido.Signal.Router.route(router, first)
    assert {:ok, instruction} = Jido.Instruction.bind(template, first.data, %{client: client, signal: first})
    assert {:ok, data} = Jido.Exec.run(instruction)
    assert {:ok, completed} = Chat.SendMessage.reply(first, data, source: client.source)
    assert :ok = Jido.Signal.Dispatch.dispatch(completed, {:pid, [target: self()]})
    assert_receive {:signal, ^completed}
    assert F.round_trip(completed) == completed
  end

  @tag obligation: "jido_chat.actions.I5"
  test "a failed Flow dependency prevents the next provider write" do
    client = F.client()
    first = F.request(Chat.SendMessage, client, %{"request_id" => "first"})
    second = F.request(Chat.SendMessage, client, %{"request_id" => "second"})

    assert {:error, _} =
             Jido.Exec.run(
               F.ReplyFlow,
               %{first: first.data, second: second.data},
               %{client: client, options: [provider_return: {:error, {:rejected, :forbidden}}]},
               max_attempts: 1
             )

    assert_receive {:contract_invoke, _, _, observed, _, _}
    assert observed.data == first.data
    refute_receive {:contract_invoke, _, _, _, _, _}
  end

  @tag obligation: "jido_chat.actions.I8"
  test "Action schemas match Signal data schemas and accept serialized data" do
    for {definition, action} <- F.pairs() do
      client = F.client()
      request = F.request(action, client)
      json = action.to_json()
      assert json["input_schema"] == F.entry(definition)["data_schema"]
      assert json["output_schema"] == F.entry(Module.concat(action, Completed))["data_schema"]
      assert action.schema() == definition.schema()
      assert action.output_schema() == Module.concat(action, Completed).schema()
      options = if action == Chat.StreamText, do: [stream: ["one", " two"]], else: []
      data = request.data |> Jason.encode!() |> Jason.decode!()

      assert {:ok, completed} =
               Jido.Exec.run(action, data, %{client: client, signal: request, options: options}, max_attempts: 1)

      assert completed["operation"] == request.type
      assert {:ok, reply} = action.reply(request, completed, source: client.source)
      assert F.round_trip(reply) == reply
      assert_receive {:contract_invoke, _, _, _, _, _}
    end
  end
end
