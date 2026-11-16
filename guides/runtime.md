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
    room_definitions: %{"support" => MyApp.SupportRoom},
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

Startup declarations and provider account declarations are in memory. Room
declarations created by `provision_room/2` are durable. Their running or stopped
desired state survives a Runtime restart. The manager resolves each stored
definition key through the static `room_definitions` map. Stored data cannot
name an Elixir module or create an atom. A normal Runtime shutdown stops its
managed Agent activations.

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

## Durable Room provisioning

Define a trusted Room registry and opt the Room Agent into its Runtime:

```elixir
defmodule MyApp.Chat do
  use Jido.Chat.Runtime,
    jido: MyApp.Jido,
    storage: {MyApp.ChatStorage, MyApp.ChatStorageResource},
    room_definitions: %{"support" => MyApp.SupportRoom}
end

defmodule MyApp.SupportRoom do
  use Jido.Chat.Runtime.Room, name: "support_room"

  room do
    admin("operator")
    runtime(MyApp.Chat)
    history_limit(100)
    member_limit(20)
  end
end
```

Provisioning commits the Room record and managed declaration together:

```elixir
{:ok, result} =
  MyApp.Chat.provision_room("support", %{
    id: "support",
    kind: :group,
    name: "Support"
  })

result.room
result.declaration
result.activation
```

`activation` is `:not_started` when the managed Runtime is not running. When it
is running, activation contains the managed Room status. Storage acceptance and
live activation are separate. A later reconcile retries a failed activation.

`start_managed_room/1` and `stop_managed_room/1` store desired state for a
durable declaration before they change its Agent activation. `deprovision_room/1`
stops the Room and removes only the declaration. It preserves the Room record,
membership, and history.

Durable provider account declarations are not supported. Provider definitions
can contain credentials and need a separate secret-reference contract.

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
    runtime(MyApp.Chat)
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

With no `runtime` setting, the Room owns in-memory membership, a bounded working
history, a local sequence, and one Jido Signal Bus. With a Runtime setting,
storage is authoritative for membership and immutable message history. The
Room state keeps a bounded working cache. A managed activation restores active
members, recent messages, and the last sequence from storage.

Query durable data through the Runtime facade:

```elixir
{:ok, members} = MyApp.Chat.list_room_memberships("support", status: :active)
{:ok, membership} = MyApp.Chat.get_room_membership("support", "alice")

{:ok, history} = MyApp.Chat.list_room_history("support", limit: 100)
{:ok, older} = MyApp.Chat.list_room_history("support", before: hd(history).message_id)
{:ok, message} = MyApp.Chat.get_room_history("support", "message-id")
```

Membership status is `:active`, `:suspended`, or `:revoked`. History order is
oldest first. `before` and `after` are exclusive message-ID cursors and cannot
be used together. `thread_id` filters one thread. `latest: true` returns the
most recent bounded page in oldest-first order. Limits are from 1 through
1,000.

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
the exact Room Address, authoritative `actor_active?` and `member_active?`
values, the `room_full?` capacity result for a join, the bounded `working_members`
cache, and private authorization options. `members` remains as an alias for the
bounded cache. A durable Room reads the actor and target membership directly.
It does not load all members for each command.
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
