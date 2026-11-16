# Runtime storage adapters

Jido Chat stores Runtime data through small domain capabilities. It does not
select Ecto, Ash, or another persistence framework for the host.

Every selection has this shape:

```elixir
{adapter_module, host_owned_resource}
```

The resource can be a process name, an Ecto Repo and schema map, an Ash Domain
and resource map, an event-store client, or another value owned by the host.
Starting `:jido_chat` does not start that resource.

## Capabilities

An adapter implements only the capabilities its Runtime use needs:

| Capability | Stored responsibility |
| --- | --- |
| `Jido.Chat.Runtime.Storage.Links` | Local-to-provider message identity |
| `Jido.Chat.Runtime.Storage.Outbox` | Provider work and compare-and-set transitions |
| `Jido.Chat.Runtime.Storage.Rooms` | Durable Room records, revision checks, and bounded queries |
| `Jido.Chat.Runtime.Storage.RoomDeclarations` | Managed Room definition keys and desired state |
| `Jido.Chat.Runtime.Storage.Memberships` | Room member lifecycle and revision checks |
| `Jido.Chat.Runtime.Storage.History` | Immutable Room message facts and bounded queries |
| `Jido.Chat.Runtime.Storage.Commit` | One atomic batch across supported capabilities |

Declare the capabilities on an adapter:

```elixir
defmodule MyApp.ChatStorage do
  alias Jido.Chat.Runtime.Storage.{
    Adapter,
    Commit,
    History,
    Links,
    Memberships,
    Outbox,
    RoomDeclarations,
    Rooms
  }

  use Adapter,
    capabilities: [Links, Outbox, Rooms, RoomDeclarations, Memberships, History, Commit]

  # Implement the callbacks from the four declared behaviours.
end
```

`Jido.Chat.Runtime.Storage.validate/2` checks the declaration and its exported
callbacks. Existing adapters that implement callbacks without the declaration
remain valid.

## Local durable storage

`Jido.Chat.Runtime.Storage.Dets` implements all current capabilities without
another package dependency. It stores non-history Runtime state in one versioned
snapshot and stores each Room history fact in a separate DETS record. It is
intended for local or single-node use.

```elixir
children = [
  {Jido.Chat.Runtime.Storage.Dets,
   name: MyApp.ChatStorage,
   table: :my_app_chat_storage,
   path: "data/chat-runtime.dets"},
  {Jido, name: MyApp.Jido, namespace: "my-app/chat"}
]

defmodule MyApp.Chat do
  use Jido.Chat.Runtime,
    jido: MyApp.Jido,
    storage: {Jido.Chat.Runtime.Storage.Dets, MyApp.ChatStorage}
end
```

The host owns the file path, backup, process, and supervision. Treat the DETS
file as trusted application data. An unsupported stored format stops the
adapter without resetting or overwriting the file.

Format 4 keeps history outside the snapshot, so a new message does not rewrite
all prior Room history. The adapter reads formats 1 through 3 and moves their
history into separate records when it opens the file.

DETS is not the scale or distributed-storage target. Use an indexed host
adapter when the application needs database queries, multi-node coordination,
tenancy, or framework migrations.

## Ecto mapping

An Ecto adapter uses a resource such as `%{repo: MyApp.Repo, schemas: ...}` and
maps each capability to its schemas and queries. Implement `Commit.commit/2`
with one `Repo.transact/2` operation only when every command in the batch uses
the same transaction boundary.

The normal mapping is:

| Chat capability | Ecto implementation shape |
| --- | --- |
| Links | Link schema with unique local and provider identities |
| Outbox | Work schema with status, lease owner, lease expiry, and compare-and-set update |
| Rooms | Room schema with unique ID, indexed insertion time and kind, and revision-checked update and delete queries |
| RoomDeclarations | Declaration schema with unique Room ID, definition key, desired state, and revision-checked changes |
| Memberships | Membership schema with unique Room and member key, status index, and revision-checked transitions |
| History | Immutable message schema with unique Room and message ID, unique Room sequence, and thread index |
| Commit | `Ecto.Multi` or a function passed to `Repo.transact/2` |

Jido Chat does not require `ecto`, `ecto_sql`, or a specific database adapter.
The host owns migrations, prefixes, tenancy, sandbox setup, and error mapping.

## Ash mapping

An Ash adapter uses a resource such as `%{domain: MyApp.Chat, resources: ...}`
and maps each capability to Ash actions. Implement `Commit.commit/2` with
`Ash.transact/3` only when the selected resources share a transaction boundary.

The normal mapping is:

| Chat capability | Ash implementation shape |
| --- | --- |
| Links | Link resource with identities for local and provider keys |
| Outbox | Work resource with atomic status and lease actions |
| Rooms | Room resource with indexed read actions and atomic revision conditions on update and delete |
| RoomDeclarations | Declaration resource with atomic desired-state and revision actions |
| Memberships | Membership resource with atomic status and revision actions |
| History | Immutable message resource with Room sequence and thread read actions |
| Commit | One transaction across the affected resource list |

Jido Chat does not require `ash` or one Ash data layer. The host owns resources,
domains, policies, tenancy, migrations, and framework error translation.

Official transaction references:

- [Ecto Repo transactions](https://ecto.hexdocs.pm/Ecto.Repo.html#transact/2)
- [Ash transactions](https://ash.hexdocs.pm/Ash.html#transact/3)

## Adapter invariants

Every adapter must preserve these rules:

- Link identities are unique in both directions.
- Outbox updates compare the expected status and allow only declared state
  transitions.
- Room IDs are unique. Insert is idempotent only when the complete stored record
  is equal.
- Room updates and deletes compare the expected revision in the same atomic
  operation. An update can change only `name` and `metadata`.
- Room lists use ascending insertion time and ID order. `:after` is an exclusive
  stored Room-ID cursor. `:limit` is from 1 through 1,000.
- A Room declaration stores a registered definition key, never executable code,
  a module name from stored data, a PID, or credentials.
- Declaration and membership changes compare the expected revision in the same
  atomic operation.
- Membership identity uses the complete portable Agent Address or a nonempty
  host principal ID. Active, suspended, and revoked are valid statuses.
- History is immutable. Room and message ID and Room sequence are unique. Query
  order is ascending sequence. `before` and `after` cursors are exclusive.
- Commit returns no partial success. Do not declare Commit if the backing data
  layer cannot make the complete batch atomic.
- Stored work keeps `lease_owner` and `lease_expires_at` while it is claimed.
- Unknown provider outcomes and submitted or terminal work are not retried
  automatically.
- Adapter failures return `{:error, reason}` and do not expose credentials or
  framework records as Chat domain results.

Use the built-in Memory and DETS tests as the conformance examples for a custom
adapter.
