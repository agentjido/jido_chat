defmodule Jido.Chat.Slack.AdapterTest do
  use Jido.Chat.AdapterTestKit, adapter: Jido.Chat.Slack.Adapter, async: true

  alias Jido.Chat.Slack.{Adapter, Operations, TestTransport}

  defp client(opts \\ []) do
    Jido.Chat.Client.new!(Adapter,
      id: "slack-#{System.unique_integer([:positive])}",
      credentials: Keyword.get(opts, :credentials, %{bot_token: "xoxb-test", app_token: "xapp-test"}),
      config: [test_pid: self(), marker: :private],
      transport: TestTransport
    )
  end

  test "client discovery is local and credentials stay private" do
    value = client()
    assert Adapter.default_transport() == Jido.Chat.Slack.Transport.ReqClient
    assert Jido.Chat.Slack.adapter() == Adapter
    assert Jido.Chat.Slack.source() == Jido.Chat.Slack.Source
    assert Jido.Chat.Slack.webhook() == Jido.Chat.Slack.Webhook
    assert :ok = Jido.Chat.Adapter.validate_capabilities(Adapter)
    refute inspect(value) =~ "xoxb-test"
  end

  test "message, stream, file, edit, and delete requests use explicit bot credentials" do
    value = client()

    assert {:ok, sent} =
             Jido.Chat.send_text(value, "C1", "hello",
               thread_id: "T1",
               keyboard: %{"rows" => [[%{"text" => "Go", "value" => "go"}]]}
             )

    assert sent.data["result"]["id"] == "1700000000.000001"

    assert_receive {:send_message, "xoxb-test", "C1", "hello", options}
    assert options[:thread_ts] == "T1"
    assert [%{"type" => "actions"}] = options[:blocks]
    assert options[:marker] == :private
    refute Keyword.has_key?(options, :bot_token)

    assert {:ok, _} = Jido.Chat.stream_text(value, "C1", ["a", "b"])
    assert_receive {:send_message, "xoxb-test", "C1", "ab", _}

    source = %{"content_base64" => Base.encode64("bytes"), "filename" => "test.txt"}
    assert {:ok, _} = Jido.Chat.send_file(value, "C1", source, caption: "file")
    assert_receive {:send_file, "xoxb-test", "C1", %{body: "bytes", filename: "test.txt"}, _}

    assert {:ok, _} = Jido.Chat.edit_message(value, "C1", "M1", "new")
    assert_receive {:edit_message, "xoxb-test", "C1", "M1", "new", _}
    assert {:ok, _} = Jido.Chat.delete_message(value, "C1", "M1")
    assert_receive {:delete_message, "xoxb-test", "C1", "M1", _}
  end

  test "queries return canonical conversation, message, user, subject, and participant values" do
    value = client()

    completed = execute(value, :fetch_metadata)

    assert completed.data["result"] == %{
             "id" => "room/1",
             "kind" => "channel",
             "name" => "general",
             "topic" => "General"
           }

    assert execute(value, :fetch_thread).data["result"]["id"] == "thread-1"
    assert execute(value, :fetch_message).data["result"]["text"] == "message"
    assert execute(value, :get_user).data["result"]["id"] == "actor-1"
    subject = operation_request(value, :fetch_subject, %{"thread_id" => "thread-1"})
    assert {:ok, subject_result} = Jido.Chat.execute(value, subject)
    assert subject_result.data["result"]["kind"] == "thread"

    participants = execute(value, :get_thread_participants).data["result"]
    assert Enum.map(participants["participants"], & &1["id"]) == ["U1", "U2"]
    assert participants["complete"]
  end

  test "pages, acknowledgements, ephemeral messages, modal, options, DM, and downloads are typed" do
    value = client()

    assert execute(value, :fetch_messages).data["result"]["next_cursor"] == "next"
    assert execute(value, :list_threads).data["result"]["complete"]

    for operation <- [:mark_as_read, :add_reaction, :remove_reaction] do
      assert execute(value, operation).data["result"] == %{"acknowledged" => true}
    end

    assert execute(value, :post_ephemeral).data["result"]["status"] == "sent"
    assert execute(value, :open_dm).data["result"] == %{"id" => "D1", "kind" => "direct"}

    modal = operation_request(value, :open_modal, %{"modal" => %{"title" => "Test"}})
    assert {:ok, modal_result} = Jido.Chat.execute(value, modal, options: [trigger_id: "TR1"])
    assert modal_result.data["result"] == %{"opened" => true, "id" => "V1"}
    assert_receive {:open_modal, "xoxb-test", "TR1", %{"type" => "modal"}, _}

    options = operation_request(value, :load_options)

    assert {:ok, options_result} =
             Jido.Chat.execute(value, options,
               options: [options_loader: fn _ -> [%{"label" => "One", "value" => "1"}] end]
             )

    assert options_result.data["result"]["options"] == [%{"label" => "One", "value" => "1"}]

    no_token = %{value | credentials: %{}}
    no_token_options = operation_request(no_token, :load_options)

    assert {:ok, _} =
             Jido.Chat.execute(no_token, no_token_options, options: [options_loader: fn _ -> [{"Local", "local"}] end])

    reference = %{"client_id" => value.id, "kind" => "media", "id" => "https://files.slack.com/F1"}
    request = operation_request(value, :download_file, %{"resource_ref" => reference})
    assert {:ok, downloaded} = Jido.Chat.execute(value, request)
    assert downloaded.data["result"]["content_base64"] == Base.encode64("file bytes")

    untrusted = Map.put(reference, "id", "https://example.com/private")
    request = operation_request(value, :download_file, %{"resource_ref" => untrusted})
    assert {:error, _} = Jido.Chat.execute(value, request)
    refute_receive {:download_file, _, "https://example.com/private", _}

    assert {:error, _} = Jido.Chat.execute(value, modal)
    refute_receive {:open_modal, _, _, _, _}
  end

  test "missing credentials and unsupported dispatch do not attempt provider I/O" do
    value = client(credentials: %{})
    request = operation_request(value, :send_message)

    assert {:error, {:not_attempted, :missing_bot_token}} =
             Operations.invoke(:send_message, value, request, [])

    assert {:error, {:not_attempted, :unsupported}} = Operations.invoke(:unknown, client(), request, [])
    assert {:error, {:not_attempted, :unsupported}} = Adapter.invoke(client(), %{request | type: "unknown"}, [])
  end

  defp execute(client, operation) do
    request = operation_request(client, operation)
    assert {:ok, completed} = Jido.Chat.execute(client, request)
    completed
  end
end
