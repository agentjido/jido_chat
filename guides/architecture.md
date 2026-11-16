# Jido Chat architecture

Jido Chat is one package with three layers. Each layer can be used without the
higher layers.

| Layer | Main modules | Responsibility |
| --- | --- | --- |
| Core | `Jido.Chat.*` | Portable values, typed Signals, Actions, rendering, Clients, and provider adapter contracts |
| Integration | `Jido.Chat.Plugin.*`, `Jido.Chat.Sensor.*` | Connect provider Clients and Sources to one Jido Agent activation |
| Runtime | `Jido.Chat.Runtime.*` | Durable Room records, local Room Agents, participants, provider accounts, bridges, durable provider work, and storage contracts |

The dependency direction is:

```text
Runtime -> Integration -> Core
Runtime ----------------> Core
```

Core does not call Integration or Runtime. Integration does not call Runtime.
The root and Runtime Boundary declarations enforce the public module boundary.
Focused architecture tests enforce rules that namespace boundaries cannot
express.

## Ownership

The host owns the Jido instance and storage resources. Starting `:jido_chat`
starts no room, Sensor, provider connection, queue, or storage process.

Jido owns Agent activation, supervision, routing, checkpoints, Plugin runtime
lifetime, Directives, and Signal Bus processes. Jido Chat owns Chat values,
provider contracts, Room and bridge policy, durable Room record values,
provider-work IDs, links, leases, status transitions, and Runtime storage
contracts.

Provider packages own transport details, provider cursors, acknowledgements,
and reconnect policy.

## Core contracts

`Jido.Chat.Post` is the portable outbound value. `Jido.Chat.Message` is the
normalized message snapshot. Portable values reject process-local terms and
must serialize to JSON after the documented DateTime, MapSet, tuple, Regex, and
atom conversions. JSON object keys must be strings or atoms. Atom keys become
strings. A value is invalid if two input keys become the same string.

One `Jido.Chat.Content` value has one selected variant. Provider adapters define
an explicit `channel_type/0` and declare operation capability status. Provider
credentials stay in `Jido.Chat.Client` and do not enter Signals or stored work.

## Integration

`Jido.Chat.Plugin` resolves immutable Clients for one Agent activation. An
optional `Jido.Chat.Sensor` reads or receives provider input. Admission checks
the declared connection, room, Signal type, identity, and authorization before
the Agent handles the Signal.

Provider commands run after Agent commit through Plugin Directives. Completion
and failure return as typed Signals. Integration does not own account lifetime,
local rooms, or durable provider retries.

## Runtime process tree

```text
Host application
|- optional Jido Chat Runtime supervisor
|  `- Runtime manager (desired state and reconciliation)
|- host-owned Jido instance
|  |- Room Agent
|  |  `- room Signal Bus
|  |- Participant Agent
|  `- provider account Agent
|     |- Chat Plugin runtime and optional Sensor
|     `- Bridge Worker and room subscriptions
`- host-owned Chat storage resource
```

The optional Runtime manager starts, stops, and reconciles declared Agent
activations through the host Jido instance. It is not an Agent supervisor. Jido
remains the only owner of Room, participant, and provider account Agent
processes. Starting `:jido_chat` does not start the Runtime supervisor.

One provider account is one Agent activation. The Bridge maps declared provider
rooms to declared local Room addresses. It does not create rooms or accounts.
Provider account declarations and startup Room declarations are in memory.
Provisioned Room declarations and their desired state are durable. Stored
declarations refer to a portable key that the host maps to trusted Room Agent
code.

Durable Room records are also separate from live Agents and managed Runtime
declarations. They give the host a stable Room identity and descriptive
metadata. Creating or deleting a record does not start or stop an Agent.

## Durable provider work

Before a Bridge Action can commit, it stores its idempotent work record in the
Outbox. The stable work ID makes repeated admission safe. The Agent Directive
then schedules the stored record.

The Worker owns recovery on every start. It refills its bounded memory queue as
tasks finish, retries transient storage failures, and reclaims expired claims.
It does not automatically retry submitted or unknown provider work.

```text
pending -> claimed -> submitted -> completed
    ^         |          |------> failed
    `---------`          `------> unknown
```

The current storage capabilities are:

- `Links` for local and provider message identity.
- `Outbox` for provider work and compare-and-set transitions.
- `Rooms` for revision-checked durable Room records and bounded catalog
  queries.
- `RoomDeclarations` for managed Room definition keys and desired state.
- `Memberships` for revision-checked Room member lifecycle.
- `History` for immutable Room message facts and bounded queries.
- `Commit` for an atomic batch across one adapter resource.

Memory and DETS implement these capabilities. An Ecto or Ash adapter can
implement the same behaviours without adding either framework to Jido Chat.
DETS stores non-history Runtime state in one snapshot and stores Room history as
separate records. A new history fact does not rewrite prior history.

There is no transaction between the Chat Outbox and the Jido checkpoint. If a
checkpoint fails after Outbox admission, pending work can remain. Stable IDs
make later admission idempotent. A future Jido recoverable-effect contract can
close this cross-store atomicity limit.

## Room publication

A Room without a Runtime keeps membership, sequence, and retained messages in
its bounded Plugin state. A durable Room uses storage as the authority and its
Plugin state as a bounded working cache. It writes membership and message facts
before Agent commit and restores the cache before managed activation. Stable
membership revisions and message IDs make retry safe if storage succeeds and a
later Agent checkpoint fails.

The Room publishes committed message Signals to its Jido Bus. Durable message
history does not make the Bus log durable. Applications that need Bus records
across restarts must also select a durable Jido Bus store.

## Delivery limits

Jido Chat does not claim exactly-once provider delivery. A provider outcome can
be unknown after submission. The host or provider adapter must reconcile that
state before it requests another provider write.

DETS is for local or single-node durability. Distributed applications must use
a host adapter with suitable transaction, lease, and tenancy support.
