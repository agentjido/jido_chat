defmodule Jido.Chat.RuntimeBridgeTest do
  use ExUnit.Case, async: false
  @moduletag capture_log: true

  alias Jido.Chat.{Content, Message, Post}
  alias Jido.Chat.Runtime.Bridge.Worker
  alias Jido.Chat.Runtime.Signal.Room.Join
  alias Jido.Chat.Runtime.Storage.Memory

  defmodule Adapter do
    use Jido.Chat.Adapter

    @impl true
    def channel_type, do: :test

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

  defmodule FailingStorage do
    use Jido.Chat.Runtime.Storage.Adapter,
      capabilities: [
        Jido.Chat.Runtime.Storage.Links,
        Jido.Chat.Runtime.Storage.Outbox,
        Jido.Chat.Runtime.Storage.Commit
      ]

    def put_link(_resource, _link), do: {:error, :storage_unavailable}
    def link_for_local(_resource, _account_id, _local_id), do: {:ok, nil}
    def link_for_external(_resource, _account_id, _room_id, _message_id), do: {:ok, nil}
    def put_work(_resource, _work), do: {:error, :storage_unavailable}
    def get_work(_resource, _id), do: {:ok, nil}
    def list_work(:admission, _account_id, _opts), do: {:ok, []}
    def list_work(:recovery, _account_id, _opts), do: {:error, :storage_unavailable}
    def update_work(_resource, _id, _status, _changes), do: {:error, :storage_unavailable}
    def commit(_resource, []), do: {:ok, []}
    def commit(_resource, _commands), do: {:error, :storage_unavailable}
  end

  defmodule FailingRuntime do
    use Jido.Chat.Runtime,
      jido: Jido.Chat.RuntimeBridgeTest.Jido,
      storage: {Jido.Chat.RuntimeBridgeTest.FailingStorage, :admission}
  end

  defmodule RecoveryFailRuntime do
    use Jido.Chat.Runtime,
      jido: Jido.Chat.RuntimeBridgeTest.Jido,
      storage: {Jido.Chat.RuntimeBridgeTest.FailingStorage, :recovery}
  end

  defmodule FlakyStorage do
    use Jido.Chat.Runtime.Storage.Adapter,
      capabilities: [
        Jido.Chat.Runtime.Storage.Links,
        Jido.Chat.Runtime.Storage.Outbox,
        Jido.Chat.Runtime.Storage.Commit
      ]

    def put_link(resource, link), do: Memory.put_link(resource.storage, link)

    def link_for_local(resource, account_id, local_id),
      do: Memory.link_for_local(resource.storage, account_id, local_id)

    def link_for_external(resource, account_id, room_id, message_id),
      do: Memory.link_for_external(resource.storage, account_id, room_id, message_id)

    def put_work(resource, work), do: Memory.put_work(resource.storage, work)
    def get_work(resource, id), do: Memory.get_work(resource.storage, id)
    def list_work(resource, account_id, opts), do: Memory.list_work(resource.storage, account_id, opts)

    def update_work(resource, id, status, changes),
      do: Memory.update_work(resource.storage, id, status, changes)

    def commit(resource, commands) do
      completion? =
        Enum.any?(commands, fn
          {:update_work, _id, :submitted, %{status: :completed}} -> true
          _command -> false
        end)

      if completion? and fail_once?(resource.failures),
        do: {:error, :temporary_storage_failure},
        else: Memory.commit(resource.storage, commands)
    end

    defp fail_once?(failures) do
      Agent.get_and_update(failures, fn
        [true | rest] -> {true, rest}
        state -> {false, state}
      end)
    end
  end

  defmodule QueueRuntime do
  end

  defmodule SettlementRuntime do
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
      plugins: [Jido.Chat.Plugin, Jido.Chat.Runtime.Bridge]

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

    {:ok, room} = Jido.agent_address(Runtime.jido(), "team")
    {:ok, room_server} = Jido.Chat.Runtime.Room.start_agent(Runtime.jido(), room, Team)
    :ok = Jido.AgentServer.await_ready(room_server)
    {:ok, account_ref} = Runtime.connection_ref("support")

    for member <- ["operator", account_ref] do
      assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
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

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.Chat.Plugin.ingest(context.account, :provider, inbound)

    message = await_room_message(context.room_server, &(Message.fallback_text(&1) =~ "From provider"))
    assert message.actor.id == "user-1"
    assert Enum.any?(message.content, &match?(%Content{kind: :media}, &1))
    assert get_in(message.metadata, ["jido_chat_origin", "account_id"]) == "support"
    refute_receive {:provider_send, _, _}, 200

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.Chat.Plugin.ingest(context.account, :provider, inbound)

    Process.sleep(100)
    assert Enum.count(room_messages(context.room_server), &(&1.id == message.id)) == 1

    assert {:ok, link} = Runtime.bridge_link("support", message.id)
    assert link.external_message_id == "provider-1"
    assert link.direction == :inbound
  end

  test "outbound messages and replies keep provider links", context do
    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} = post(context, Post.text("To provider"))

    assert_receive {:provider_send, "bridge/client", first_request}, 2_000
    assert first_request.data["room_id"] == "provider-room"
    assert first_request.data["text"] == "To provider"
    refute Map.has_key?(first_request.data, "reply_to_id")

    first = await_room_message(context.room_server, &(Message.fallback_text(&1) == "To provider"))
    first_link = await_link(first.id)

    inbound = incoming("provider-reply", "Provider reply", reply_to_id: first_link.external_message_id)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.Chat.Plugin.ingest(context.account, :provider, inbound)

    provider_reply = await_room_message(context.room_server, &(Message.fallback_text(&1) == "Provider reply"))
    assert provider_reply.reply_to_id == first.id
    refute_receive {:provider_send, _, _}, 200

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             post(context, Post.text("Local reply", reply_to_id: provider_reply.id))

    assert_receive {:provider_send, "bridge/client", reply_request}, 2_000
    assert reply_request.data["reply_to_id"] == "provider-reply"
    local_reply = await_room_message(context.room_server, &(Message.fallback_text(&1) == "Local reply"))
    assert await_link(local_reply.id).direction == :outbound
  end

  test "unknown provider outcomes are retained and are not sent again", context do
    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} = post(context, Post.text("Unknown outcome"))
    assert_receive {:provider_send, "bridge/client", request}, 2_000
    await(fn -> match?({:ok, %{unknown: 1}}, Runtime.bridge_status("support")) end)
    assert :ok = Runtime.recover_bridge("support")
    request_id = request.data["request_id"]

    refute_receive {:provider_send, "bridge/client", %{data: %{"request_id" => ^request_id}}},
                   300

    assert {:ok, %{unknown: 1, pending: 0, submitted: 0}} = Runtime.bridge_status("support")
  end

  test "Bridge admission fails the turn before an unavailable Outbox can lose work", context do
    {:ok, account_ref} = FailingRuntime.connection_ref("failing-admission")

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(
               context.jido,
               context.room,
               Join.new!(%{"member" => account_ref}),
               context: %{actor: "operator"}
             )

    assert {:ok, ^account_ref, account} =
             FailingRuntime.start_connection("failing-admission", Account)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed}} =
             Jido.Chat.Plugin.ingest(account, :provider, incoming("not-stored", "Not stored", []))

    assert {:ok, %{total: 0}} = FailingRuntime.bridge_status("failing-admission")
    refute Enum.any?(room_messages(context.room_server), &(Message.fallback_text(&1) == "Not stored"))
  end

  test "Worker startup and restart drain a backlog beyond the memory queue limit", context do
    account_id = "queue-recovery"

    for index <- 1..5 do
      assert {:ok, _work} =
               Memory.put_work(
                 __MODULE__.Storage,
                 inbound_work(context, account_id, "queued-#{index}", :pending)
               )
    end

    data = %{
      runtime: QueueRuntime,
      storage: {Memory, __MODULE__.Storage},
      account_id: account_id,
      account_ref: "operator",
      client_id: "queue/client",
      client_source: "urn:jido:chat:client:queue",
      jido: context.jido,
      mappings: [],
      limit: 1,
      queue_limit: 2,
      lease_ms: 200
    }

    worker =
      start_supervised!(Supervisor.child_spec({Worker, data}, id: :queue_recovery_worker))

    await(fn ->
      match?(
        {:ok, work} when length(work) == 5,
        Memory.list_work(__MODULE__.Storage, account_id, status: :completed)
      )
    end)

    expiring = inbound_work(context, account_id, "after-restart", :claimed)
    expiring = Map.merge(expiring, %{lease_owner: "dead", lease_expires_at: System.system_time(:millisecond) + 200})
    assert {:ok, ^expiring} = Memory.put_work(__MODULE__.Storage, expiring)

    monitor = Process.monitor(worker)
    Process.exit(worker, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}

    await(fn ->
      case :global.whereis_name({Worker, QueueRuntime, account_id}) do
        pid when is_pid(pid) -> pid != worker
        :undefined -> false
      end
    end)

    await(fn ->
      match?({:ok, %{status: :completed}}, Memory.get_work(__MODULE__.Storage, "after-restart"))
    end)
  end

  test "Worker retries a transient post-task storage result", context do
    failures = start_supervised!({Agent, fn -> [true] end}, id: :settlement_failures)
    account_id = "settlement-retry"
    resource = %{storage: __MODULE__.Storage, failures: failures}

    data = %{
      runtime: SettlementRuntime,
      storage: {FlakyStorage, resource},
      account_id: account_id,
      account_ref: "operator",
      client_id: "settlement/client",
      client_source: "urn:jido:chat:client:settlement",
      jido: context.jido,
      mappings: [],
      limit: 1,
      queue_limit: 1,
      lease_ms: 200
    }

    worker =
      start_supervised!(Supervisor.child_spec({Worker, data}, id: :settlement_retry_worker))

    assert :ok = Worker.enqueue(worker, inbound_work(context, account_id, "settlement-work", :pending))

    await(fn ->
      match?({:ok, %{status: :completed}}, Memory.get_work(__MODULE__.Storage, "settlement-work"))
    end)

    assert [] = Agent.get(failures, & &1)
  end

  test "a failed recovery removes the account Agent created by start", context do
    assert {:error, :storage_unavailable} =
             RecoveryFailRuntime.start_connection("failed-start", Account)

    {:ok, ref} = RecoveryFailRuntime.connection_ref("failed-start")
    assert {:error, :not_found} = Jido.resolve_agent(context.jido, ref)
  end

  test "pending work resumes when the account Agent starts again", context do
    assert :ok = Runtime.stop_connection("support")
    await(fn -> Runtime.connection_status("support") == {:error, :not_found} end)

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

  test "recovery reclaims expired and legacy claims but protects a live lease" do
    now = System.system_time(:millisecond)

    for {id, lease} <- [
          {"expired-claim", %{lease_owner: "old-worker", lease_expires_at: now - 1}},
          {"legacy-claim", %{}},
          {"live-claim", %{lease_owner: "live-worker", lease_expires_at: now + 60_000}}
        ] do
      request =
        Jido.Chat.Signal.SendMessage.new!(%{
          "client_id" => "bridge/client",
          "request_id" => id,
          "room_id" => "provider-room",
          "text" => id
        })

      work =
        Map.merge(
          %{
            id: id,
            kind: :outbound,
            account_id: "support",
            mapping: :team,
            local_message_id: "local-" <> id,
            external_room_id: "provider-room",
            signal: request,
            status: :claimed
          },
          lease
        )

      assert {:ok, ^work} = Memory.put_work(__MODULE__.Storage, work)
    end

    assert :ok = Runtime.recover_bridge("support")

    assert_receive {:provider_send, "bridge/client", %{data: %{"request_id" => "expired-claim"}}},
                   2_000

    assert_receive {:provider_send, "bridge/client", %{data: %{"request_id" => "legacy-claim"}}},
                   2_000

    refute_receive {:provider_send, "bridge/client", %{data: %{"request_id" => "live-claim"}}},
                   300

    assert await_link("local-expired-claim").external_room_id == "provider-room"
    assert await_link("local-legacy-claim").external_room_id == "provider-room"
    assert {:ok, %{claimed: 1, completed: 2, pending: 0}} = Runtime.bridge_status("support")

    assert {:ok, %{status: :claimed, lease_owner: "live-worker"}} =
             Memory.get_work(__MODULE__.Storage, "live-claim")
  end

  test "recovery retries an inactive claim when its lease expires" do
    request =
      Jido.Chat.Signal.SendMessage.new!(%{
        "client_id" => "bridge/client",
        "request_id" => "expiring-claim",
        "room_id" => "provider-room",
        "text" => "retry after lease"
      })

    work = %{
      id: "expiring-claim",
      kind: :outbound,
      account_id: "support",
      mapping: :team,
      local_message_id: "local-expiring-claim",
      external_room_id: "provider-room",
      signal: request,
      status: :claimed,
      lease_owner: "old-worker",
      lease_expires_at: System.system_time(:millisecond) + 500
    }

    assert {:ok, ^work} = Memory.put_work(__MODULE__.Storage, work)
    assert :ok = Runtime.recover_bridge("support")

    refute_receive {:provider_send, "bridge/client", %{data: %{"request_id" => "expiring-claim"}}},
                   100

    assert_receive {:provider_send, "bridge/client", %{data: %{"request_id" => "expiring-claim"}}},
                   2_000

    assert await_link("local-expiring-claim").external_room_id == "provider-room"
  end

  test "failed room and account turns retain unknown work without provider I/O", context do
    worker = Jido.Chat.Runtime.Bridge.Worker.server(Runtime, "support")
    signal = Jido.Signal.new!("test.chat.unhandled", %{}, source: "urn:test:chat")

    for kind <- [:inbound, :outbound] do
      id = "failed-turn-" <> Atom.to_string(kind)

      work = %{
        id: id,
        kind: kind,
        account_id: "support",
        room: context.room,
        signal: signal,
        link: %{},
        status: :pending
      }

      assert :ok = Jido.Chat.Runtime.Bridge.Worker.enqueue(worker, work)
      await(fn -> match?({:ok, %{status: :unknown}}, Memory.get_work(__MODULE__.Storage, id)) end)
      assert {:ok, %{status: :unknown, last_error: :operation_failed}} = Memory.get_work(__MODULE__.Storage, id)
    end

    assert :ok = Runtime.recover_bridge("support")
    refute_receive {:provider_send, _, _}, 100
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

    assert {:ok, %{total: 0, pending: 0}} = Runtime.bridge_status("support")
  end

  test "connection lifetime is owned by the host Jido instance", context do
    account = context.account
    account_ref = context.account_ref
    assert {:error, {:already_started, ^account}} = Runtime.start_connection("support", Account)
    assert {:ok, %{account_id: "support", ref: ^account_ref}} = Runtime.connection_status("support")
    assert :ok = Runtime.stop_connection("support")
    await(fn -> Runtime.connection_status("support") == {:error, :not_found} end)
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

  defp inbound_work(context, account_id, id, status) do
    post = Post.text(id, metadata: %{"jido_chat_origin" => %{"account_id" => "support"}})

    signal =
      Jido.Chat.Runtime.Signal.Room.Post.new!(
        %{"post" => Post.to_map(post), "mentions" => []},
        id: id
      )

    %{
      id: id,
      kind: :inbound,
      account_id: account_id,
      room: context.room,
      signal: signal,
      link: %{
        account_id: account_id,
        mapping: :queue,
        local_message_id: id,
        external_room_id: "queue-room",
        external_message_id: "external-#{id}",
        direction: :inbound
      },
      status: status
    }
  end

  defp room_messages(server) do
    server
    |> Jido.AgentServer.snapshot()
    |> Map.fetch!(:agent)
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
