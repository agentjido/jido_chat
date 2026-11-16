# Jido Chat architecture

Jido Chat is one package with three layers. Each layer can be used without the
higher layers.

| Layer | Main modules | Responsibility |
| --- | --- | --- |
| Core | `Jido.Chat.*` | Portable values, typed Signals, Actions, rendering, Clients, and provider adapter contracts |
| Integration | `Jido.Chat.Plugin.*`, `Jido.Chat.Sensor.*` | Connect provider Clients and Sources to one Jido Agent activation |
| Runtime | `Jido.Chat.Runtime.*` | Local rooms, participants, provider accounts, bridges, durable provider work, and storage contracts |

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
provider contracts, Room and bridge policy, provider-work IDs, links, leases,
status transitions, and the storage contract for durable provider work.

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
|- host-owned Jido instance
|  |- Room Agent
|  |  `- room Signal Bus
|  |- Participant Agent
|  `- provider account Agent
|     |- Chat Plugin runtime and optional Sensor
|     `- Bridge Worker and room subscriptions
`- host-owned Chat storage resource
```

One provider account is one Agent activation. The Bridge maps declared provider
rooms to declared local Room addresses. It does not create rooms or accounts.

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
- `Commit` for an atomic batch across one adapter resource.

Memory and DETS implement these capabilities. An Ecto or Ash adapter can
implement the same behaviours without adding either framework to Jido Chat.

There is no transaction between the Chat Outbox and the Jido checkpoint. If a
checkpoint fails after Outbox admission, pending work can remain. Stable IDs
make later admission idempotent. A future Jido recoverable-effect contract can
close this cross-store atomicity limit.

## Room publication

A Room keeps bounded membership, sequence, and retained message state in its
Plugin field. It publishes committed message Signals to its Jido Bus. Repeating
the same Post ID and data republishes the retained Signal without adding another
history entry. Applications that need Bus records across restarts must select a
durable Jido Bus store.

## Delivery limits

Jido Chat does not claim exactly-once provider delivery. A provider outcome can
be unknown after submission. The host or provider adapter must reconcile that
state before it requests another provider write.

DETS is for local or single-node durability. Distributed applications must use
a host adapter with suitable transaction, lease, and tenancy support.
