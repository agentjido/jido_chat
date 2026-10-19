defmodule Jido.Chat.OperationsAPITest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true
  alias Jido.Chat.{Client, Signal}

  defmodule Adapter do
    use Jido.Chat.Adapter

    def capabilities do
      Map.new(
        [
          :edit_message,
          :delete_message,
          :download_file,
          :add_reaction,
          :remove_reaction,
          :fetch_metadata,
          :start_typing,
          :create_thread
        ],
        &{&1, :native}
      )
    end

    def normalize(_, _, _), do: {:error, :unused}

    def invoke(_client, request, opts) do
      send(opts[:observer], {:request, request, opts})

      result =
        cond do
          request.type == Signal.EditMessage.type() ->
            %{
              "id" => request.data["message_id"],
              "room_id" => request.data["room_id"],
              "text" => request.data["text"],
              "status" => "updated"
            }

          request.type == Signal.DownloadFile.type() ->
            %{"content_base64" => Base.encode64("downloaded bytes")}

          request.type == Signal.FetchMetadata.type() ->
            %{"id" => request.data["room_id"], "kind" => "group", "name" => "Support"}

          request.type == Signal.CreateThread.type() ->
            %{"id" => "topic-1", "room_id" => request.data["room_id"], "name" => request.data["name"]}

          true ->
            %{"acknowledged" => true}
        end

      {:ok, result}
    end
  end

  defmodule Unsupported do
    use Jido.Chat.Adapter
    def capabilities, do: %{}
    def normalize(_, _, _), do: {:error, :unused}
    def invoke(_, _, _), do: raise("must not call provider")
  end

  defp client(adapter \\ Adapter), do: Client.new!(adapter, id: "test", credentials: %{token: "private-token"})
  defp ref(client_id \\ "test"), do: %{"client_id" => client_id, "kind" => "media", "id" => "file-1"}

  test "edit_message uses the existing command with formatting, keyboard, and trace context" do
    trace = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
    keyboard = %{"rows" => []}

    assert {:ok, completed} =
             Jido.Chat.edit_message(client(), "room", "message", "**Done**",
               request_id: "edit:1",
               format: :markdown,
               keyboard: keyboard,
               signal_options: [extensions: %{"traceparent" => trace}],
               options: [observer: self(), private_setting: "local"]
             )

    assert_receive {:request, request, [observer: _, private_setting: "local"]}
    assert request.type == Signal.EditMessage.type()

    assert request.data == %{
             "client_id" => "test",
             "request_id" => "edit:1",
             "room_id" => "room",
             "message_id" => "message",
             "text" => "**Done**",
             "format" => "markdown",
             "keyboard" => keyboard
           }

    assert completed.data["result"] == %{
             "id" => "message",
             "room_id" => "room",
             "text" => "**Done**",
             "status" => "updated"
           }

    assert completed.extensions["traceparent"] == trace
    assert completed.extensions["causationid"] == request.id
    assert_completed(completed, Signal.EditMessage)
  end

  test "delete and reaction functions preserve message identity and return acknowledgement Signals" do
    for {function, args, definition} <- [
          {:delete_message, ["room", "message"], Signal.DeleteMessage},
          {:add_reaction, ["room", "message", "👍"], Signal.AddReaction},
          {:remove_reaction, ["room", "message", "👍"], Signal.RemoveReaction}
        ] do
      assert {:ok, completed} = apply(Jido.Chat, function, [client() | args] ++ [[options: [observer: self()]]])
      assert_receive {:request, request, _}
      assert request.type == definition.type()
      assert request.data["room_id"] == "room"
      assert request.data["message_id"] == "message"
      if function != :delete_message, do: assert(request.data["reaction"] == "👍")
      assert Jido.Signal.ID.valid?(request.data["request_id"])
      assert completed.data["request_id"] == request.data["request_id"]
      assert completed.data["result"] == %{"acknowledged" => true}
      assert_completed(completed, definition)
    end
  end

  test "download_file keeps the resource reference in the query and bytes in its completion" do
    assert {:ok, completed} =
             Jido.Chat.download_file(client(), ref(), request_id: "download:1", options: [observer: self()])

    assert_receive {:request, request, _}
    assert request.type == Signal.DownloadFile.type()
    assert request.data == %{"client_id" => "test", "request_id" => "download:1", "resource_ref" => ref()}
    assert Base.decode64!(completed.data["result"]["content_base64"]) == "downloaded bytes"
    assert_completed(completed, Signal.DownloadFile)

    assert {:error, %Jido.Chat.Errors.Contract{code: :context_mismatch}} =
             Jido.Chat.download_file(client(), ref("another-client"), options: [observer: self()])

    refute_receive {:request, _, _}
  end

  test "fetch_metadata preserves query and trace context without exposing private options" do
    trace = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

    assert {:ok, completed} =
             Jido.Chat.fetch_metadata(client(), "room",
               request_id: "metadata:1",
               signal_options: [extensions: %{"traceparent" => trace}],
               options: [observer: self(), private_setting: "local"]
             )

    assert_receive {:request, request, [observer: _, private_setting: "local"]}
    assert request.type == Signal.FetchMetadata.type()
    assert request.data == %{"client_id" => "test", "request_id" => "metadata:1", "room_id" => "room"}
    assert completed.data["result"] == %{"id" => "room", "kind" => "group", "name" => "Support"}
    assert completed.extensions["traceparent"] == trace
    assert completed.extensions["causationid"] == request.id
    assert_completed(completed, Signal.FetchMetadata)
    refute_receive {:request, _, _}
  end

  test "create_thread returns an ID that start_typing can address without retained state" do
    assert {:ok, created} =
             Jido.Chat.create_thread(client(), "room", "Release", options: [observer: self()])

    assert_receive {:request, request, _}
    assert request.type == Signal.CreateThread.type()
    assert request.data["name"] == "Release"
    assert Jido.Signal.ID.valid?(request.data["request_id"])
    assert created.data["request_id"] == request.data["request_id"]
    assert created.data["result"] == %{"id" => "topic-1", "room_id" => "room", "name" => "Release"}
    assert_completed(created, Signal.CreateThread)

    assert {:ok, typing} =
             Jido.Chat.start_typing(client(), "room",
               thread_id: created.data["result"]["id"],
               request_id: "typing:1",
               options: [observer: self()]
             )

    assert_receive {:request, typing_request, _}
    assert typing_request.type == Signal.StartTyping.type()

    assert typing_request.data == %{
             "client_id" => "test",
             "request_id" => "typing:1",
             "room_id" => "room",
             "thread_id" => "topic-1"
           }

    assert typing.data["result"] == %{"acknowledged" => true}
    assert_completed(typing, Signal.StartTyping)
    refute_receive {:request, _, _}
  end

  test "start_typing can address a room without a thread" do
    assert {:ok, completed} = Jido.Chat.start_typing(client(), "room", options: [observer: self()])
    assert_receive {:request, request, _}
    refute Map.has_key?(request.data, "thread_id")
    assert Jido.Signal.ID.valid?(request.data["request_id"])
    assert_completed(completed, Signal.StartTyping)
    refute_receive {:request, _, _}
  end

  test "capabilities reports every core operation without calling the provider" do
    capabilities = Jido.Chat.capabilities(client())
    assert capabilities[:edit_message] == :native
    assert capabilities[:delete_message] == :native
    assert capabilities[:download_file] == :native
    assert capabilities[:add_reaction] == :native
    assert capabilities[:remove_reaction] == :native
    assert capabilities[:fetch_metadata] == :native
    assert capabilities[:start_typing] == :native
    assert capabilities[:create_thread] == :native
    assert capabilities[:fetch_messages] == :unsupported
    assert map_size(capabilities) == length(Jido.Chat.actions())
    assert Enum.all?(Jido.Chat.capabilities(client(Unsupported)), fn {_, status} -> status == :unsupported end)
    refute_receive {:request, _, _}
  end

  test "unsupported operations return the existing failure Signals without provider calls" do
    for {function, args, definition} <- [
          {:edit_message, ["room", "message", "Done"], Signal.EditMessage},
          {:delete_message, ["room", "message"], Signal.DeleteMessage},
          {:download_file, [ref()], Signal.DownloadFile},
          {:add_reaction, ["room", "message", "👍"], Signal.AddReaction},
          {:remove_reaction, ["room", "message", "👍"], Signal.RemoveReaction},
          {:fetch_metadata, ["room"], Signal.FetchMetadata},
          {:start_typing, ["room"], Signal.StartTyping},
          {:create_thread, ["room", "Release"], Signal.CreateThread}
        ] do
      assert {:error, %Jido.Chat.Error{code: :unsupported, signal: failed}} =
               apply(Jido.Chat, function, [client(Unsupported) | args])

      assert failed.type == definition.type() <> ".failed"
      assert failed.data["outcome"] == "not_attempted"
      assert {:ok, json} = Jido.Signal.Serialization.serialize(failed)
      assert {:ok, ^failed} = Jido.Signal.Catalog.decode(Jido.Chat.catalog(), json)
    end
  end

  test "operation-specific invalid input and unrelated options fail before provider calls" do
    for {function, args, opts} <- [
          {:edit_message, ["room", "message", "Done"], [thread_id: "cannot-move"]},
          {:edit_message, ["room", "message", "Done"], [format: :unknown]},
          {:delete_message, ["room", ""], []},
          {:download_file, [%{"id" => "incomplete"}], []},
          {:add_reaction, ["room", "message", ""], []},
          {:remove_reaction, ["room", "message", "👍"], [request_id: "a", request_id: "b"]},
          {:fetch_metadata, [""], []},
          {:fetch_metadata, ["room"], [thread_id: "not-room-metadata"]},
          {:start_typing, ["room"], [thread_id: ""]},
          {:start_typing, ["room"], [interval_ms: 1000]},
          {:create_thread, ["room", ""], []},
          {:create_thread, ["room", "Release"], [thread_id: "existing-thread"]}
        ] do
      assert {:error, _} = apply(Jido.Chat, function, [client() | args] ++ [opts ++ [options: [observer: self()]]])
    end

    refute_receive {:request, _, _}
  end

  defp assert_completed(signal, definition) do
    assert signal.type == definition.type() <> ".completed"
    assert signal.data["operation"] == definition.type()
    assert signal.data["client_id"] == "test"
    assert {:ok, json} = Jido.Signal.Serialization.serialize(signal)
    assert {:ok, ^signal} = Jido.Signal.Catalog.decode(Jido.Chat.catalog(), json)
    refute json =~ "private-token"
    refute json =~ "private_setting"
  end
end
