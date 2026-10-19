defmodule Jido.Chat.PublicAPIContractTest do
  use Covenant.Case, component: "jido_chat.public_api", async: true
  @moduletag capture_log: true
  alias Jido.Chat
  alias Jido.Chat.ContractFixtures, as: F

  @exports __DIR__ |> Path.join("fixtures/public_exports.json") |> File.read!() |> Jason.decode!()

  @tag obligation: "jido_chat.public_api.I1"
  test "documented SDK functions and macros keep their explicit arities" do
    for {name, expected} <- @exports do
      module = F.module(name)
      assert F.public_exports(module) == expected, "public exports changed for #{name}"
    end

    for name <- [:binding, :resources, :request_store, :handlers, :subscribe, :start_link], arity <- 0..4 do
      refute function_exported?(Chat, name, arity)
    end
  end

  @tag obligation: "jido_chat.public_api.I2"
  test "all eleven helpers execute matching Actions with public data and private options" do
    keyboard = %{"rows" => [[%{"text" => "Confirm", "value" => "confirm"}]]}

    for id <- ["alpha", "beta"] do
      client = F.client(F.FirstAdapter, id)
      reference = %{"client_id" => id, "kind" => "media", "id" => "file-1"}
      source = %{"content_base64" => Base.encode64("bytes"), "filename" => "report.txt"}

      calls = [
        {:send_text, ["room/1", "Hello"], Chat.SendMessage,
         %{
           "room_id" => "room/1",
           "text" => "Hello",
           "format" => "markdown",
           "thread_id" => "thread-1",
           "reply_to_id" => "parent-1",
           "keyboard" => keyboard
         }, [format: :markdown, thread_id: "thread-1", reply_to_id: "parent-1", keyboard: keyboard]},
        {:stream_text, ["room/1", ["one", " two"]], Chat.StreamText,
         %{"room_id" => "room/1", "format" => "plain", "update_interval_ms" => 0},
         [format: :plain, update_interval_ms: 0]},
        {:send_file, ["room/1", source], Chat.SendFile,
         %{"room_id" => "room/1", "source" => source, "caption" => "Report", "media_kind" => "file"},
         [caption: "Report", media_kind: :file]},
        {:edit_message, ["room/1", "message-1", "Updated"], Chat.EditMessage,
         %{
           "room_id" => "room/1",
           "message_id" => "message-1",
           "text" => "Updated",
           "format" => "html",
           "keyboard" => %{"rows" => []}
         }, [format: :html, keyboard: %{"rows" => []}]},
        {:delete_message, ["room/1", "message-1"], Chat.DeleteMessage,
         %{"room_id" => "room/1", "message_id" => "message-1"}, []},
        {:download_file, [reference], Chat.DownloadFile, %{"resource_ref" => reference}, []},
        {:add_reaction, ["room/1", "message-1", "👍"], Chat.AddReaction,
         %{"room_id" => "room/1", "message_id" => "message-1", "reaction" => "👍"}, []},
        {:remove_reaction, ["room/1", "message-1", "👍"], Chat.RemoveReaction,
         %{"room_id" => "room/1", "message_id" => "message-1", "reaction" => "👍"}, []},
        {:fetch_metadata, ["room/1"], Chat.FetchMetadata, %{"room_id" => "room/1"}, []},
        {:start_typing, ["room/1"], Chat.StartTyping, %{"room_id" => "room/1", "thread_id" => "thread-1"},
         [thread_id: "thread-1"]},
        {:create_thread, ["room/1", "Support"], Chat.CreateThread, %{"room_id" => "room/1", "name" => "Support"}, []}
      ]

      for {function, args, action, fields, specific} <- calls do
        opts =
          specific ++
            [
              request_id: "explicit",
              signal_options: [extensions: %{"traceparent" => F.trace()}],
              options: [local_setting: "private-config"],
              timeout: :infinity
            ]

        assert {:ok, completed} = apply(Chat, function, [client | args] ++ [opts])
        assert_receive {:contract_invoke, F.FirstAdapter, ^id, request, private, _}
        assert request.type == action.signal_definition().type()
        assert request.data == Map.merge(fields, %{"client_id" => id, "request_id" => "explicit"})
        assert request.source == client.source
        assert private[:local_setting] == "private-config"
        assert completed.type == Module.concat(action, Completed).type()
        assert completed.data["operation"] == request.type
        assert completed.data["client_id"] == id
        assert completed.data["request_id"] == "explicit"
        assert completed.extensions["traceparent"] == F.trace()
        assert completed.extensions["jidocausationid"] == request.id
        assert F.round_trip(completed) == completed
      end
    end
  end

  @tag obligation: "jido_chat.public_api.I3"
  test "generated IDs are fresh and explicit IDs do not suppress repeated writes" do
    client = F.client()
    for _ <- 1..2, do: assert({:ok, _} = Chat.send_text(client, "room/1", "Hello"))
    assert_receive {:contract_invoke, _, _, first, _, _}
    assert_receive {:contract_invoke, _, _, second, _, _}
    assert Jido.Signal.ID.valid?(first.data["request_id"])
    assert Jido.Signal.ID.valid?(second.data["request_id"])
    refute first.data["request_id"] == second.data["request_id"]

    for _ <- 1..2 do
      assert {:ok, completed} = Chat.send_text(client, "room/1", "Again", request_id: "repeat")
      assert completed.data["request_id"] == "repeat"
      assert_receive {:contract_invoke, _, _, request, _, _}
      assert request.data["request_id"] == "repeat"
    end
  end

  @tag obligation: "jido_chat.public_api.I4"
  test "invalid helper and execution options fail before provider calls" do
    client = F.client()

    calls = [
      {:send_text, ["room/1", "Hello"]},
      {:stream_text, ["room/1", ["Hello"]]},
      {:send_file, ["room/1", %{"content_base64" => "YQ==", "filename" => "a.txt"}]},
      {:edit_message, ["room/1", "m", "Updated"]},
      {:delete_message, ["room/1", "m"]},
      {:download_file, [%{"client_id" => client.id, "kind" => "media", "id" => "f"}]},
      {:add_reaction, ["room/1", "m", "👍"]},
      {:remove_reaction, ["room/1", "m", "👍"]},
      {:fetch_metadata, ["room/1"]},
      {:start_typing, ["room/1"]},
      {:create_thread, ["room/1", "Name"]}
    ]

    for {function, args} <- calls,
        opts <- [
          [unknown: true],
          [request_id: "a", request_id: "b"],
          [options: :bad],
          [signal_options: [type: "override"]],
          [timeout: -1],
          [timeout: "1"]
        ] do
      assert {:error, %Chat.Errors.Contract{}} = apply(Chat, function, [client | args] ++ [opts])
    end

    for opts <- [[legacy_private: true], [timeout: 1, timeout: 2], [options: :bad], [timeout: -1]] do
      assert {:error, %Chat.Errors.Contract{}} = Chat.execute(client, F.request(Chat.SendMessage, client), opts)
    end

    refute_receive {:contract_invoke, _, _, _, _, _}
  end

  @tag obligation: "jido_chat.public_api.I5"
  test "a resource stream is private, consumed once, and closed by one execution task" do
    caller = self()

    chunks =
      Stream.resource(
        fn ->
          send(caller, :opened)
          ["one", " two"]
        end,
        fn
          [] ->
            {:halt, []}

          [head | tail] ->
            send(caller, {:pulled, head, self()})
            {[head], tail}
        end,
        fn _ -> send(caller, :closed) end
      )

    assert {:ok, completed} = Chat.stream_text(F.client(), "room/1", chunks)
    assert completed.data["result"]["text"] == "one two"
    assert_receive {:contract_invoke, _, _, request, private, task}
    assert Enumerable.impl_for(private[:stream])
    refute Map.has_key?(request.data, "stream")
    assert F.round_trip(request) == request
    assert_receive :opened
    assert_receive {:pulled, "one", ^task}
    assert_receive {:pulled, " two", ^task}
    assert_receive :closed
    refute Process.alive?(task)
    refute_receive :opened
    refute_receive {:pulled, _, _}

    assert {:error, %Chat.Error{code: :unsupported}} =
             Chat.stream_text(F.client(F.UnsupportedAdapter), "room/1", chunks)

    refute_receive :opened
    refute_receive :unsupported_provider_called
  end

  @tag obligation: "jido_chat.public_api.I6"
  test "a blocked call returns a typed unknown deadline failure with one attempt" do
    client = F.client()

    assert {:error, %Chat.Error{code: :timeout, signal: failed}} =
             Chat.send_text(client, "room/1", "Hello",
               request_id: "deadline",
               timeout: 100,
               options: [provider_return: :block]
             )

    assert_receive {:contract_invoke, _, _, request, _, task}
    assert failed.type == Chat.SendMessage.Failed.type()

    assert failed.data == %{
             "client_id" => client.id,
             "request_id" => "deadline",
             "operation" => request.type,
             "code" => "timeout",
             "outcome" => "unknown"
           }

    assert failed.extensions["jidocausationid"] == request.id
    assert F.round_trip(failed) == failed
    refute Process.alive?(task)
    refute_receive {:contract_invoke, _, _, _, _, _}
  end
end
