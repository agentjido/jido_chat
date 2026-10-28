# Jido Chat Runtime

`Jido.Chat.Runtime` supplies local rooms, participants, provider account
activation, room bridges, provider work, and small storage contracts.

Runtime is optional. Starting `:jido_chat` starts no process, table, room,
queue, or storage resource. The host starts one Jido instance and each selected
storage resource.

## Runtime facade

Start the host resources in the application supervision tree:

```elixir
children = [
  {Jido, name: MyApp.Jido, namespace: "my-app/chat"},
  {Jido.Chat.Runtime.Storage.Memory, name: MyApp.ChatStorage}
]
```

Define a process-free facade:

```elixir
defmodule MyApp.Chat do
  use Jido.Chat.Runtime,
    jido: MyApp.Jido,
    storage: {Jido.Chat.Runtime.Storage.Memory, MyApp.ChatStorage},
    provider_work_limit: 4,
    provider_queue_limit: 1_000
end
```

The Memory adapter is for local and test use. The host owns its process and
lifetime. An Ecto adapter and migrations are deferred.

## Portable values

Runtime room messages use the same portable Core values as provider bridges:

- `Jido.Chat.Actor`
- `Jido.Chat.Content`
- `Jido.Chat.FileSource`
- `Jido.Chat.Media`
- `Jido.Chat.Message`
- `Jido.Chat.Post`
- `Jido.Chat.ResourceRef`

Each value has `new/1`, `to_map/1`, and `from_map/1`. `Message.fallback_text/1`
and `Post.fallback_text/1` give a deterministic text form for providers that
accept only text.

## Local room

Define a Room Agent:

```elixir
defmodule MyApp.SupportRoom do
  use Jido.Chat.Runtime.Room, name: "support_room"

  room do
    admin("operator")
    history_limit(100)
    member_limit(20)
  end
end
```

The host starts the room through its Jido instance. Join and post operations
must include the trusted caller in Jido context:

```elixir
{:ok, room} = Jido.agent_ref(MyApp.Jido, "support")
{:ok, room_server} = Jido.start_agent_ref(MyApp.Jido, room, MyApp.SupportRoom)
:ok = Jido.AgentServer.await_ready(room_server)

join = Jido.Chat.Runtime.Signal.Room.Join.new!(%{"member" => "operator"})
{:ok, _, _} = Jido.call(MyApp.Jido, room, join, context: %{actor: "operator"})

post = Jido.Chat.Post.text("Hello")
signal = Jido.Chat.Runtime.Signal.Room.Post.new!(%{
  "post" => Jido.Chat.Post.to_map(post),
  "mentions" => []
})

{:ok, _, _} = Jido.call(MyApp.Jido, room, signal,
  context: %{actor: "operator"})
```

The Room owns membership, a bounded working history, a local sequence, and one
Jido Signal Bus. Its Signal types use the `jido.chat.room.*` prefix.

## Participant

Add `Jido.Chat.Runtime.Participant` to an Agent that observes a room:

```elixir
defmodule MyApp.Observer do
  use Jido.Agent,
    name: "support_observer",
    extensions: [Jido.Chat.Runtime.Participant]

  participant do
    room("support")
    respond(:never)
    history_limit(20)
  end

  routes do
    route("jido.chat.room.message", Jido.Chat.Runtime.Actions.ReceiveMessage)
  end
end
```

The host must join the participant Agent Ref before it starts the participant.
The participant rejects forged room facts and facts received after it leaves.

## Provider account and Bridge

One provider account is one Agent activation with exactly one
`Jido.Chat.Plugin` connection. A Bridge is another Plugin on that Agent:

```elixir
defmodule MyApp.SupportAccount do
  use Jido.Agent,
    name: "support_account",
    extensions: [Jido.Chat.Plugin, Jido.Chat.Runtime.Bridge]

  chat do
    connection :provider do
      client(MyProvider.Adapter,
        id: "provider/support",
        credentials: %{token: env("PROVIDER_TOKEN")})

      rooms(["external-support"])
      commands([Jido.Chat.SendMessage])
    end
  end

  bridge do
    mapping :support do
      external_room("external-support")
      room("support")
      direction(:both)
    end
  end

  routes do
    route("jido.chat.message.received",
      Jido.Chat.Runtime.Actions.BridgeInbound)

    route("jido.chat.room.message",
      Jido.Chat.Runtime.Actions.BridgeOutbound)

    route("jido.chat.command.send_message", Jido.Chat.Plugin.Execute)

    route("jido.chat.command.send_message.completed",
      Jido.Chat.Runtime.Actions.BridgeResult)

    route("jido.chat.command.send_message.failed",
      Jido.Chat.Runtime.Actions.BridgeResult)
  end
end
```

Get the stable account Ref and join it to the local room before activation:

```elixir
{:ok, account_ref} = MyApp.Chat.connection_ref("support")

join = Jido.Chat.Runtime.Signal.Room.Join.new!(%{"member" => account_ref})
{:ok, _, _} = Jido.call(MyApp.Jido, room, join,
  context: %{actor: "operator"})

{:ok, ^account_ref, account_server} =
  MyApp.Chat.start_connection("support", MyApp.SupportAccount)
```

The Bridge preserves provider actor, media, reply, thread, and origin data. It
does not create rooms. It ignores provider self-messages and blocks an inbound
message from returning to the same provider account.

## Provider work and recovery

Provider work uses explicit states:

```text
pending -> claimed -> submitted -> completed | failed | unknown
```

Only pending work is recovered when an account starts or when the host calls
`recover_bridge/1`. Submitted, completed, failed, and unknown work is not sent
again automatically.

```elixir
{:ok, status} = MyApp.Chat.bridge_status("support")
:ok = MyApp.Chat.recover_bridge("support")
{:ok, link} = MyApp.Chat.bridge_link("support", local_message_id)
{:ok, connection} = MyApp.Chat.connection_status("support")
:ok = MyApp.Chat.stop_connection("support")
```

The storage selection must implement the capabilities required by the selected
Runtime feature. The built-in Memory adapter implements History, Links,
Outbox, Rooms, and Commit. `Commit` applies one storage batch atomically.
