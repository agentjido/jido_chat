defmodule Jido.Chat.ActionsContractTest do
  use Covenant.Case, component: "jido_chat.actions", async: true
  @moduletag capture_log: true
  alias Jido.Chat
  alias Jido.Chat.ContractFixtures, as: F

  @tag obligation: "jido_chat.actions.I1"
  test "every core Action executes and validates a completion for two client identities" do
    assert Chat.operations() == F.pairs()
    assert Enum.sort(Chat.actions()) == F.pairs() |> Enum.map(&elem(&1, 1)) |> Enum.sort()

    for id <- ["alpha", "beta"], {_definition, action} <- F.pairs() do
      client = F.client(F.FirstAdapter, id)
      request = F.request(action, client)
      options = if action == Chat.StreamText, do: [stream: ["one", " two"]], else: []

      assert {:ok, %{signal: completed}} =
               Jido.Exec.run(action, %{signal: request}, %{client: client, options: options}, max_attempts: 1)

      assert_receive {:contract_invoke, F.FirstAdapter, ^id, ^request, ^options, _}
      assert completed.type == Module.concat(action, Completed).type()
      assert completed.data["operation"] == request.type
      assert completed.data["client_id"] == id
      assert completed.data["request_id"] == request.data["request_id"]
      assert completed.source == client.source
      assert completed.extensions["traceparent"] == F.trace()
      assert completed.extensions["tracestate"] == "contract=fixture"
      assert completed.extensions["causationid"] == request.id
      assert {:ok, _} = action.validate_output(%{signal: completed})
      assert {:error, _} = action.validate_output(%{signal: request})
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
      assert {:error, _} = Jido.Exec.run(Chat.SendMessage, %{signal: bad}, %{client: client}, max_attempts: 1)
    end

    assert {:error, _} = Jido.Exec.run(Chat.SendMessage, %{signal: request}, %{}, max_attempts: 1)

    assert {:error, _} =
             Jido.Exec.run(Chat.SendMessage, %{signal: request}, %{client: client, options: [:bad]}, max_attempts: 1)

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
      assert failed.extensions["causationid"] == request.id

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
             Jido.Exec.run(F.ReplyFlow, %{first: first, second: second}, %{client: client}, max_attempts: 1)

    assert_receive {:contract_invoke, _, _, observed_first, _, _}
    assert observed_first == first
    assert_receive {:contract_invoke, _, _, observed_second, _, _}
    assert observed_second == second
    assert first_result.extensions["causationid"] == first.id
    assert second_result.extensions["causationid"] == second.id

    router = Jido.Signal.Router.new!([{Chat.Signal.SendMessage, Jido.Instruction.template(:action, Chat.SendMessage)}])
    assert {:ok, [template]} = Jido.Signal.Router.route(router, first)
    assert {:ok, instruction} = Jido.Instruction.bind(template, %{signal: first}, %{client: client})
    assert {:ok, %{signal: completed}} = Jido.Exec.run(instruction)
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
               %{first: first, second: second},
               %{client: client, options: [provider_return: {:error, {:rejected, :forbidden}}]},
               max_attempts: 1
             )

    assert_receive {:contract_invoke, _, _, observed, _, _}
    assert observed == first
    refute_receive {:contract_invoke, _, _, _, _, _}
  end

  @tag obligation: "jido_chat.actions.I6"
  test "agent schemas pin exact wire shapes and accept their serialized request examples" do
    for {definition, action} <- F.pairs() do
      client = F.client()
      request = F.request(action, client)
      json = action.to_json()

      for {key, entry} <- [
            {"input_schema", F.entry(definition)},
            {"output_schema", F.entry(Module.concat(action, Completed))}
          ] do
        envelope = json[key]["properties"]["signal"]
        assert envelope["additionalProperties"] == false
        assert Enum.sort(envelope["required"]) == Enum.sort(~w(id source type dataschema data))
        assert envelope["properties"]["type"]["const"] == entry["type"]
        assert envelope["properties"]["dataschema"]["const"] == entry["dataschema"]
        assert envelope["properties"]["data"] == entry["data_schema"]

        assert Map.keys(envelope["properties"]) --
                 ~w(id source type specversion subject time datacontenttype dataschema data traceparent tracestate causationid) ==
                 []
      end

      assert {:ok, encoded} = Jido.Signal.Serialization.serialize(request)
      options = if action == Chat.StreamText, do: [stream: ["one", " two"]], else: []

      assert {:ok, %{signal: completed}} =
               Jido.Exec.run(action, %{"signal" => Jason.decode!(encoded)}, %{client: client, options: options},
                 max_attempts: 1
               )

      assert completed.data["operation"] == request.type
      assert_receive {:contract_invoke, _, _, _, _, _}
    end

    client = F.client()
    request = F.request(Chat.SendMessage, client)
    wire = Jido.Signal.to_map(request)

    for bad <- [
          Map.put(wire, "token", "private-token"),
          Map.put(wire, "type", Chat.Signal.DeleteMessage.type()),
          Map.put(wire, "dataschema", "urn:unknown:1"),
          put_in(wire, ["data", "text"], 42)
        ] do
      assert {:error, _} = Jido.Exec.run(Chat.SendMessage, %{"signal" => bad}, %{client: client}, max_attempts: 1)
    end

    refute_receive {:contract_invoke, _, _, _, _, _}
  end
end
