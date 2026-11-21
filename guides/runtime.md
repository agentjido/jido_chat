# Jido Chat Runtime

`Jido.Chat.Runtime` supplies local rooms, participants, provider account
activation, room bridges, provider work, one observation Bus, and small storage
contracts.

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
    connection_definitions: %{"provider" => MyApp.SupportAccount},
    secret_resolver: MyApp.ChatSecrets,
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

The Runtime supervisor starts one bounded `Jido.Signal.Bus` and then one
manager. The manager declares the required state. It starts, resolves, and
stops Agents only through `MyApp.Jido`. The Room and provider account Agent
processes remain below the Jido process tree. Set `:bus_max_log_size` on the
Runtime child to change the default 10,000-record memory bound.

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

Startup declarations are in memory. Room declarations created by
`provision_room/2` and provider declarations created by
`provision_connection/2` are durable. Their running or stopped desired state
survives a Runtime restart. The manager resolves each stored definition key
through the applicable static definition map. Stored data cannot name an
Elixir module or create an atom. A normal Runtime shutdown stops its managed
Agent activations.

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
membership, history, and reactions.

Durable provider account declarations store a trusted definition key, secret
references, portable settings, desired state, and revision. The host resolves
each secret reference when it starts the provider Agent. Jido Chat does not
store the resolved credential.

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

{:ok, reactions} =
  MyApp.Chat.list_room_reactions("support",
    message_id: "message-id",
    status: :active
  )

{:ok, reaction} =
  MyApp.Chat.get_room_reaction("support", "message-id", "eyes", "alice")
```

Membership status is `:active`, `:suspended`, or `:revoked`. History order is
oldest first. `before` and `after` are exclusive message-ID cursors and cannot
be used together. `thread_id` filters one thread. `latest: true` returns the
most recent bounded page in oldest-first order. Limits are from 1 through
1,000.

Reaction state is a separate durable projection. A reaction identity is the
Room ID, message ID, reaction value, and complete actor identity. Add and remove
operations update a revision-checked current-state record. Removed records stay
as tombstones. They are not deleted.

An active Room member can add or remove only that member's reaction on a
message that exists in the same durable Room history. Use
`Jido.Chat.Runtime.Signal.Room.AddReaction` and `RemoveReaction` with the
trusted caller in `context.actor`. A real state change publishes the canonical
`jido.chat.reaction.added` or `jido.chat.reaction.removed` fact after storage
succeeds. A repeated request returns `changed: false` and does not publish a
second fact.

Reaction list options are `:message_id` or up to 100 unique `:message_ids`,
`:status`, `:after`, and `:limit`. The cursor is the stable reaction record ID.
The maximum result limit is 1,000. The default facade query returns only active
reactions. Set `status: :removed` to read tombstones.

Threads are a projection of immutable Room history. A message keeps its
`thread_id`, and `list_room_history/2` can filter that value. Jido Chat does not
store a separate thread record.

### Runtime-wide realtime

Each Room keeps its isolated Bus for Agent interaction. A durable Room also
publishes each committed `jido.chat.room.message` and changed canonical
reaction fact to the managed Runtime Bus. The exact Signal is reused. Jido Chat
does not add another event wrapper.

Subscribe through the Runtime facade:

```elixir
{:ok, bus} = MyApp.Chat.runtime_bus()

{:ok, subscription_id} =
  MyApp.Chat.subscribe_runtime("jido.chat.room.message")

receive do
  {:signal, %Jido.Signal{} = fact} ->
    room_id = fact.data["room"].id
    {:ok, history} = MyApp.Chat.list_room_history(room_id, latest: true, limit: 100)
end

:ok = MyApp.Chat.unsubscribe_runtime(subscription_id)
```

`subscribe_runtime/2` passes native Jido Bus options through unchanged. A host
can set `:target` or a Signal selector. `runtime_bus/0` returns the native Bus
PID when the host needs another supported Jido Bus operation.

Storage is authoritative. Runtime Bus delivery is a notification to read the
durable projection again. A missing or restarting Runtime Bus does not roll
back a stored message or reaction. The built-in Runtime Bus uses bounded memory,
so a host reattaches its subscriptions after a Runtime restart.

Presence stays in the host. Assembly can update Phoenix Presence or another
session system when a client connects, disconnects, or sends a heartbeat. It
can use committed Chat facts to refresh views, but it must not turn presence
changes into durable Room membership or add Phoenix to Jido Chat.

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

### Durable provider provisioning

A durable provider Agent can keep an empty trusted Room list and an empty
compiled Bridge mapping list. Runtime replaces both lists with enabled durable
bindings when it starts the Agent. The trusted Agent must still declare the
Chat and Bridge Plugins and all required routes.

Define a host resolver. It returns credentials for one activation and does not
store them in Jido Chat:

```elixir
defmodule MyApp.ChatSecrets do
  @behaviour Jido.Chat.Runtime.SecretResolver

  @impl true
  def resolve(%{"token" => reference}, context) do
    MyApp.Secrets.credentials(reference, account_id: context.account_id)
  end
end
```

Provision the account with an opaque reference. Stored settings can replace
only keys that already exist in the trusted Chat client configuration.

```elixir
{:ok, %{declaration: declaration, activation: activation}} =
  MyApp.Chat.provision_connection("provider", %{
    account_id: "support",
    secret_refs: %{"token" => "vault://chat/support"},
    settings: %{"poll_interval" => 5_000},
    metadata: %{"owner" => "support"}
  })

{:ok, %{binding: binding}} =
  MyApp.Chat.create_bridge_binding(%{
    account_id: "support",
    room_id: "support",
    external_room_id: "external-support",
    direction: :both
  })
```

Connection identity is the account ID. Binding identity is the account ID and
external Room ID. One local Room can have many outbound bindings. Runtime
sorts those bindings by external Room ID and creates one provider work item for
each binding.

Update calls require the current revision. A changed connection or binding
revision replaces the live Agent configuration on the next reconcile.

```elixir
{:ok, %{declaration: declaration}} =
  MyApp.Chat.update_connection_declaration(
    "support",
    declaration.revision,
    %{settings: %{"poll_interval" => 10_000}}
  )

{:ok, bindings} = MyApp.Chat.list_bridge_bindings("support", enabled: true)
{:ok, %{binding: disabled, activation: activation}} =
  MyApp.Chat.deprovision_bridge_binding("support", binding.external_room_id)
:ok = MyApp.Chat.deprovision_connection("support")
```

Deprovisioning stores stopped or disabled state. It does not delete Room
history, provider work, links, declarations, or bindings. Resolved credentials
do not appear in declarations, status maps, or Runtime storage.

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
{:ok, links} = MyApp.Chat.bridge_links("support", local_message_id)
{:ok, connection} = MyApp.Chat.connection_status("support")
:ok = MyApp.Chat.stop_connection("support")
```

The storage selection must implement the capabilities required by the selected
Runtime feature. The built-in Memory and DETS adapters implement all Runtime
capabilities, including Connections and Bindings. `Commit` applies one storage
batch atomically.

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

## Move from Jido Messaging

Jido Chat Runtime replaces the room and provider bridge roles of
`jido_messaging`. Start a Jido instance and a Runtime under your application
supervisor. Migrate the host in one change before you remove its
`:jido_messaging` dependency.

| Existing integration | Jido Chat V3 integration |
| --- | --- |
| Room server, membership, and message writes | Provision managed Rooms. Use Room commands for membership, messages, threads, and reactions. Check the committed turn result. |
| Provider handlers and bridge configuration | Declare provider accounts and bind their external conversations to Rooms. Add each provider account Agent as a Room member before relay starts. Use a Sensor or host-owned webhook input. |
| Messaging subscriptions | Use the Runtime Bus for committed Room facts. Update consumers to the `jido.chat.room.*` signal types. |
| Messaging persistence | Choose a Runtime storage adapter for the required capabilities. Export and convert existing records before cutover. Runtime has no automatic import for the legacy tables. |
| Presence and application-specific records | Keep presence, search projections, and application-specific identity, trust, and workflow records in the host. Use Runtime authorization and secret resolution at the Chat boundary. |

Use the [provider migration guide](providers.md) for adapter dependencies and
configuration. Test a Room write, a committed Signal subscription, and each
configured provider relay against a copy of the host setup before cutover.
