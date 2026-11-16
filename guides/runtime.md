# Jido Chat Runtime

`Jido.Chat.Runtime` supplies local rooms, participants, provider account
activation, room bridges, provider work, and small storage contracts.

Runtime is optional. Starting `:jido_chat` starts no process, table, room,
queue, or storage resource. The host starts one Jido instance and each selected
storage resource. The host can also start the Runtime facade to manage declared
Room and provider account Agent activations.

## Runtime facade

Define a Runtime facade:

```elixir
defmodule MyApp.Chat do
  use Jido.Chat.Runtime,
    jido: MyApp.Jido,
    storage: {Jido.Chat.Runtime.Storage.Dets, MyApp.ChatStorage},
    provider_work_limit: 4,
    provider_queue_limit: 1_000,
    provider_work_lease_ms: 60_000
end
```

Start the host resources in the application supervision tree. Start Jido and
storage before the optional managed Runtime:

```elixir
children = [
  {Jido, name: MyApp.Jido, namespace: "my-app/chat"},
  {Jido.Chat.Runtime.Storage.Dets,
   name: MyApp.ChatStorage,
   table: :my_app_chat_storage,
   path: "data/chat-runtime.dets"},
  {MyApp.Chat,
   rooms: [{"support", MyApp.SupportRoom}],
   connections: [{"support", MyApp.SupportAccount}],
   reconcile_interval: 5_000}
]
```

The Runtime supervisor owns one manager. The manager declares the required
state. It starts, resolves, and stops Agents only through `MyApp.Jido`. The Room
and provider account Agent processes remain below the Jido process tree.

The initial reconcile starts rooms before provider accounts. One failed entry
does not stop another entry. The manager retries failed entries at the selected
positive `:reconcile_interval`. Use `:infinity` only when the host will call
`reconcile_runtime/0` itself.

Use the managed lifecycle through the facade:

```elixir
{:ok, status} = MyApp.Chat.runtime_status()
{:ok, rooms} = MyApp.Chat.list_managed_rooms()
{:ok, connections} = MyApp.Chat.list_managed_connections()

{:ok, room} = MyApp.Chat.stop_managed_room("support")
{:ok, room} = MyApp.Chat.start_managed_room("support")
{:ok, room} = MyApp.Chat.restart_managed_room("support")

{:ok, account} = MyApp.Chat.stop_managed_connection("support")
{:ok, account} = MyApp.Chat.start_managed_connection("support")
{:ok, account} = MyApp.Chat.restart_managed_connection("support")

{:ok, status} = MyApp.Chat.reconcile_runtime()
```

Managed declarations and manual desired state are in memory. A Runtime manager
restart restores the startup declarations and their initial running state. It
adopts matching Agent activations that remain under Jido. A normal Runtime
shutdown stops its managed Agent activations. A durable declaration catalog is
not part of this contract.

The managed functions are separate from `start_connection/2`,
`stop_connection/1`, and `connection_status/1`. Those functions keep the direct
process-free contract. Do not use a direct stop for a managed account because
the next reconcile will start the declared account again.

The host owns the storage process and lifetime. The DETS adapter is durable
local, single-node storage. Memory remains available for tests and ephemeral
use. An application can implement the same capability behaviours with Ecto,
Ash resources, an event store, or another persistence system. See the
[storage adapter guide](storage_adapters.md).

## Durable Room records

A Runtime with a Rooms-capable storage adapter has a durable Room catalog:

```elixir
{:ok, room} =
  MyApp.Chat.create_room(%{
    kind: :group,
    name: "Support",
    metadata: %{visibility: "private"}
  })

{:ok, ^room} = MyApp.Chat.get_room(room.id)
{:ok, rooms} = MyApp.Chat.list_rooms(kind: :group, limit: 50)
{:ok, next_page} = MyApp.Chat.list_rooms(after: List.last(rooms).id, limit: 50)

{:ok, room} =
  MyApp.Chat.update_room(room.id, room.revision, %{name: "Customer Support"})

:ok = MyApp.Chat.delete_room(room.id, room.revision)
```

Room kinds are `:direct`, `:group`, `:channel`, and `:thread`. List order is
oldest first by insertion time and Room ID. The `:after` cursor is exclusive
and must name a stored Room. The default limit is 100 and the maximum is 1,000.

An update can change only the name and metadata. Update and delete operations
compare the record revision. A stale revision returns `:room_conflict`.

A durable Room record is not a live Room Agent or a managed Runtime
declaration. Record deletion does not stop an Agent. It also does not delete
membership, message history, Bus data, or provider data. Use
`list_managed_rooms/0` to inspect live managed Room declarations. Use
`list_rooms/1` to query durable Room records.

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

The managed Runtime can start a declared room. A host that does not start the
managed Runtime can start the room directly through its Jido instance. Join and
post operations must include the trusted caller in Jido context:

```elixir
{:ok, room} = Jido.agent_address(MyApp.Jido, "support")
{:ok, room_server} = Jido.Chat.Runtime.Room.start_agent(MyApp.Jido, room, MyApp.SupportRoom)
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

### Room identity and authorization

The default Room configuration preserves local behavior. It resolves the
trusted `context.actor` and applies the administrator and membership rules
through `Jido.Chat.Authorizer.Room`.

A host can replace identity resolution without changing Room state:

```elixir
defmodule MyApp.SupportRoom do
  use Jido.Chat.Runtime.Room, name: "support_room"

  room do
    admin("operator")
    identity_provider(MyApp.ChatIdentity)
    authorizer(MyApp.ChatAuthorizer)
  end
end
```

The host supplies a provider-scoped source in caller context:

```elixir
context = %{
  identity_source: %{
    provider: "web",
    account_id: "my-app",
    external_id: authenticated_user.id,
    room_id: room.id
  }
}

Jido.call(MyApp.Jido, room, signal, context: context)
```

The configured identity provider maps this source to a
`Jido.Chat.Principal`. The authorizer receives the principal, the Room action,
the exact Room Address, current membership, and private authorization options.
The principal and decision are transient. Stored Room membership and message
shapes do not contain credentials or external profiles.

`Jido.Chat.Authorizer.RoomRoles` supplies an optional owner, admin, moderator,
member, and guest policy for hosts that put these local role names on the
principal. A host can replace it with its existing policy module.

## Participant

Add `Jido.Chat.Runtime.Participant` to an Agent that observes a room:

```elixir
defmodule MyApp.Observer do
  use Jido.Agent,
    name: "support_observer",
    plugins: [Jido.Chat.Runtime.Participant]

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

The host must join the participant Agent Address before it starts the participant.
The participant rejects forged room facts and facts received after it leaves.

## Provider account and Bridge

One provider account is one Agent activation with exactly one
`Jido.Chat.Plugin` connection. A Bridge is another Plugin on that Agent:

```elixir
defmodule MyApp.SupportAccount do
  use Jido.Agent,
    name: "support_account",
    plugins: [Jido.Chat.Plugin, Jido.Chat.Runtime.Bridge]

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
`recover_bridge/1`. An expired claimed item first returns to pending. A live
claim stays claimed. Submitted, completed, failed, and unknown work is not sent
again automatically.

```elixir
{:ok, status} = MyApp.Chat.bridge_status("support")
:ok = MyApp.Chat.recover_bridge("support")
{:ok, link} = MyApp.Chat.bridge_link("support", local_message_id)
{:ok, connection} = MyApp.Chat.connection_status("support")
:ok = MyApp.Chat.stop_connection("support")
```

The storage selection must implement the capabilities required by the selected
Runtime feature. The built-in Memory and DETS adapters implement Links, Outbox,
Rooms, and Commit. `Commit` applies one storage batch atomically.

## Correlated room results

Core Agent calls return `{:ok, %Jido.AgentServer.TurnResult{}}`. Check the turn
status before you use its result. A committed turn can still have pending
post-commit effects.

A Post turn returns a reply with type `jido.chat.room.posted`. Its data is
`%{"message" => %Jido.Signal{}}`. This is the exact room message fact from that
turn. The reply's `jidocausationid` is the Post request ID. A repeated Post with
the same ID and data returns and republishes the original fact without adding
another entry to Room history.

`Jido.Chat.Runtime.Room.check_member/4` checks membership and an optional retained
message in one room turn. Its typed `jido.chat.room.member_checked` reply contains
`%{"member" => boolean, "retained" => boolean}` and the request causation ID.
The helper returns `:ok` only for a committed, correlated positive reply.
Agent identities use `Jido.Agent.Address`. Version-1 stored identity maps keep
`version`, `namespace`, `partition`, and `id` keys.
