defmodule Jido.Chat.RuntimeBridgeTest do
  use ExUnit.Case, async: false
  @moduletag capture_log: true

  alias Jido.Chat.{Content, Message, Post}
  alias Jido.Chat.Runtime.Signal.Room.Join
  alias Jido.Chat.Runtime.Storage.Memory

  defmodule Adapter do
    use Jido.Chat.Adapter

    @impl true
    def capabilities, do: %{send_message: :native}

    @impl true
    def normalize(_client, _payload, _opts), do: {:error, :unused}

    @impl true
    def invoke(client, request, _opts) do
      send(Jido.Chat.RuntimeBridgeTest, {:provider_send, client.id, request})

      if request.data["text"] == "Unknown outcome" do
        {:error, {:unknown, :timeout, %{}}}
      else
        {:ok,
         %{
           "id" => "provider/" <> request.data["request_id"],
           "room_id" => request.data["room_id"],
           "text" => request.data["text"],
           "reply_to_id" => request.data["reply_to_id"]
         }
         |> Enum.reject(fn {_key, value} -> is_nil(value) end)
         |> Map.new()}
      end
    end
  end

  defmodule Runtime do
    use Jido.Chat.Runtime,
      jido: Jido.Chat.RuntimeBridgeTest.Jido,
      storage: {Memory, Jido.Chat.RuntimeBridgeTest.Storage},
      provider_work_limit: 2,
      provider_queue_limit: 20
  end

  defmodule Team do
    use Jido.Chat.Runtime.Room, name: "bridge_team"

    room do
      admin("operator")
      history_limit(30)
      member_limit(10)
    end
  end

  defmodule Account do
    use Jido.Agent,
      name: "bridge_account",
      extensions: [Jido.Chat.Plugin, Jido.Chat.Runtime.Bridge]

    chat do
      connection :provider do
        client(Adapter, id: "bridge/client", credentials: %{})
        rooms(["provider-room"])
        commands([Jido.Chat.SendMessage])
      end
    end

    bridge do
      mapping :team do
        external_room("provider-room")
        room("team")
        direction(:both)
      end
    end

    routes do
      route("jido.chat.message.received", Jido.Chat.Runtime.Actions.BridgeInbound)
      route("jido.chat.room.message", Jido.Chat.Runtime.Actions.BridgeOutbound)
      route("jido.chat.command.send_message", Jido.Chat.Plugin.Execute)
      route("jido.chat.command.send_message.completed", Jido.Chat.Runtime.Actions.BridgeResult)
      route("jido.chat.command.send_message.failed", Jido.Chat.Runtime.Actions.BridgeResult)
    end
  end

  setup do
    {:ok, _} = Application.ensure_all_started(:jido)
    Process.register(self(), __MODULE__)
    start_supervised!({Jido, name: __MODULE__.Jido, namespace: "chat-runtime-bridge-test"})
    start_supervised!({Memory, name: __MODULE__.Storage})

    {:ok, room} = Jido.agent_ref(Runtime.jido(), "team")
    {:ok, room_server} = Jido.start_agent_ref(Runtime.jido(), room, Team)
    :ok = Jido.AgentServer.await_ready(room_server)
    {:ok, account_ref} = Runtime.connection_ref("support")

    for member <- ["operator", account_ref] do
      assert {:ok, _, _} =
               Jido.call(
                 Runtime.jido(),
                 room,
                 Join.new!(%{"member" => member}),
                 context: %{actor: "operator"}
               )
    end

    assert {:ok, ^account_ref, account} = Runtime.start_connection("support", Account)

    %{
      jido: Runtime.jido(),
      room: room,
      room_server: room_server,
      account: account,
      account_ref: account_ref
    }
  end

  test "inbound rich content enters the local room once and does not echo", context do
    inbound = incoming("provider-1", "From provider", media: true)
    assert {:ok, _, _} = Jido.Chat.Plugin.ingest(context.account, :provider, inbound)

    message = await_room_message(context.room_server, &(Message.fallback_text(&1) =~ "From provider"))
    assert message.actor.id == "user-1"
    assert Enum.any?(message.content, &match?(%Content{kind: :media}, &1))
    assert get_in(message.metadata, ["jido_chat_origin", "account_id"]) == "support"
    refute_receive {:provider_send, _, _}, 200

    assert {:ok, _, _} = Jido.Chat.Plugin.ingest(context.account, :provider, inbound)
    Process.sleep(100)
    assert Enum.count(room_messages(context.room_server), &(&1.id == message.id)) == 1

    assert {:ok, link} = Runtime.bridge_link("support", message.id)
    assert link.external_message_id == "provider-1"
    assert link.direction == :inbound
  end

  test "outbound messages and replies keep provider links", context do
    assert {:ok, _, _} = post(context, Post.text("To provider"))

    assert_receive {:provider_send, "bridge/client", first_request}, 2_000
    assert first_request.data["room_id"] == "provider-room"
    assert first_request.data["text"] == "To provider"
    refute Map.has_key?(first_request.data, "reply_to_id")

    first = await_room_message(context.room_server, &(Message.fallback_text(&1) == "To provider"))
    first_link = await_link(first.id)

    inbound = incoming("provider-reply", "Provider reply", reply_to_id: first_link.external_message_id)
    assert {:ok, _, _} = Jido.Chat.Plugin.ingest(context.account, :provider, inbound)
    provider_reply = await_room_message(context.room_server, &(Message.fallback_text(&1) == "Provider reply"))
    assert provider_reply.reply_to_id == first.id
    refute_receive {:provider_send, _, _}, 200

    assert {:ok, _, _} = post(context, Post.text("Local reply", reply_to_id: provider_reply.id))
    assert_receive {:provider_send, "bridge/client", reply_request}, 2_000
    assert reply_request.data["reply_to_id"] == "provider-reply"
    local_reply = await_room_message(context.room_server, &(Message.fallback_text(&1) == "Local reply"))
    assert await_link(local_reply.id).direction == :outbound
  end

  test "unknown provider outcomes are retained and are not sent again", context do
    assert {:ok, _, _} = post(context, Post.text("Unknown outcome"))
    assert_receive {:provider_send, "bridge/client", request}, 2_000
    await(fn -> match?({:ok, %{unknown: 1}}, Runtime.bridge_status("support")) end)
    assert :ok = Runtime.recover_bridge("support")
    request_id = request.data["request_id"]

    refute_receive {:provider_send, "bridge/client", %{data: %{"request_id" => ^request_id}}},
                   300

    assert {:ok, %{unknown: 1, pending: 0, submitted: 0}} = Runtime.bridge_status("support")
  end

  test "pending work resumes when the account Agent starts again", context do
    assert :ok = Runtime.stop_connection("support")

    request =
      Jido.Chat.Signal.SendMessage.new!(%{
        "client_id" => "bridge/client",
        "request_id" => "recovery-request",
        "room_id" => "provider-room",
        "text" => "Recovered"
      })

    work = %{
      id: "recovery-request",
      kind: :outbound,
      account_id: "support",
      mapping: :team,
      local_message_id: "recovery-local",
      external_room_id: "provider-room",
      signal: request,
      status: :pending
    }

    assert {:ok, ^work} = Memory.put_work(__MODULE__.Storage, work)
    assert {:ok, %{pending: 1}} = Runtime.bridge_status("support")
    assert {:ok, account_ref, replacement} = Runtime.start_connection("support", Account)
    assert account_ref == context.account_ref
    refute replacement == context.account

    assert_receive {:provider_send, "bridge/client", %{data: %{"request_id" => "recovery-request"}}},
                   2_000

    assert await_link("recovery-local").external_room_id == "provider-room"
    assert {:ok, %{completed: 1, pending: 0}} = Runtime.bridge_status("support")
  end

  test "provider work rejects invalid input and uncorrelated completion" do
    worker = Jido.Chat.Runtime.Bridge.Worker.server(Runtime, "support")

    assert {:error, :invalid_provider_work} =
             Jido.Chat.Runtime.Bridge.Worker.enqueue(worker, %{id: "invalid"})

    assert {:error, :work_not_found} =
             Jido.Chat.Runtime.Bridge.Worker.finish(
               worker,
               "missing",
               :completed,
               %{"result" => %{"id" => "external"}}
             )

    assert {:error, :work_not_found} =
             Jido.Chat.Runtime.Bridge.Worker.finish(
               worker,
               "missing",
               :failed,
               %{"code" => "timeout", "outcome" => "unknown"}
             )

    assert {:ok, %{total: 0, pending: 0}} = Jido.Chat.Runtime.Bridge.Worker.status(worker)
  end

  test "connection lifetime is owned by the host Jido instance", context do
    account = context.account
    account_ref = context.account_ref
    assert {:error, {:already_started, ^account}} = Runtime.start_connection("support", Account)
    assert {:ok, %{account_id: "support", ref: ^account_ref}} = Runtime.connection_status("support")
    assert :ok = Runtime.stop_connection("support")
    assert {:error, :not_found} = Runtime.connection_status("support")
    assert {:error, :connection_not_started} = Runtime.recover_bridge("support")
  end

  defp incoming(message_id, text, opts) do
    data = %{
      "item_id" => "item/" <> message_id,
      "delivery_id" => "delivery/" <> message_id,
      "room_id" => "provider-room",
      "message_id" => message_id,
      "sender" => %{
        "id" => "user-1",
        "username" => "user",
        "display_name" => "Provider User",
        "is_self" => false
      },
      "text" => text,
      "reply_to_id" => opts[:reply_to_id],
      "media" => if(opts[:media], do: [media()], else: nil)
    }

    data = data |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()

    Jido.Chat.Signal.MessageReceived.new!(data,
      source: Jido.Chat.Signal.Identity.client_source("bridge/client")
    )
  end

  defp media do
    %{
      "kind" => "image",
      "resource_ref" => %{
        "id" => "image-1",
        "client_id" => "bridge/client",
        "kind" => "media"
      },
      "name" => "example.png",
      "media_type" => "image/png",
      "caption" => "Screenshot"
    }
  end

  defp post(context, value) do
    signal = Jido.Chat.Runtime.Signal.Room.Post.new!(%{"post" => Post.to_map(value), "mentions" => []})
    Jido.call(context.jido, context.room, signal, context: %{actor: "operator"})
  end

  defp room_messages(server) do
    server
    |> Jido.AgentServer.agent()
    |> get_in([Access.key!(:state), Access.key!(:room), Access.key!(:messages)])
    |> Enum.map(&Message.from_map(&1.data["message"]))
  end

  defp await_room_message(server, check) do
    await(fn -> Enum.any?(room_messages(server), check) end)
    Enum.find(room_messages(server), check)
  end

  defp await_link(local_id) do
    await(fn -> match?({:ok, %{}}, Runtime.bridge_link("support", local_id)) end)
    {:ok, link} = Runtime.bridge_link("support", local_id)
    link
  end

  defp await(check, remaining \\ 300)
  defp await(_check, 0), do: flunk("bridge did not settle")

  defp await(check, remaining) do
    unless check.() do
      Process.sleep(10)
      await(check, remaining - 1)
    end
  end
end
