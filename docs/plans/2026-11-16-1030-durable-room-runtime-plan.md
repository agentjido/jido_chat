---
title: Add durable room runtime state
type: implementation-plan
date: 2026-11-16
last_reviewed: 2026-11-16
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Add durable room runtime state

## Goal Capsule

- Objective: Make Room declarations, provisioning, membership, and message history survive Runtime and VM restarts.
- Means: Add narrow storage capabilities, a trusted Room-definition registry, managed Runtime reconciliation, and storage-backed Room Agent working state.
- Authority: Write and test local `jido_chat` files. Do not add a package, change Jido Core, change a sibling project, create another commit, push, tag, release, or publish.
- Stop conditions: Stop if the work needs stored executable module names, stored credentials, a new dependency, a Jido Core change, or an unsafe data conversion.
- Next executor: Jido Chat implementer and independent verifier.

## Product Contract

### Problem Frame

The managed Runtime now owns a process manager and durable descriptive Room records. Its Room declarations still exist only in startup options. Room membership and bounded message history still exist only in one active Room Agent. A host cannot provision a Room once, restart the system, and recover the Room process and its interaction state.

### Requirements

- **R1:** A host declares a static map from portable definition keys to trusted Room Agent modules. Durable data stores the key, not an Elixir module name.
- **R2:** A durable Room declaration stores Room ID, definition key, desired state, revision, and UTC timestamps. It stores no PID, credential, provider account, or Agent snapshot.
- **R3:** Provisioning writes the descriptive Room record and its Room declaration in one storage commit. A failed command writes neither value.
- **R4:** The manager loads durable Room declarations, resolves them through the host registry, and reconciles desired Room state through the host-owned Jido instance.
- **R5:** Start and stop operations persist desired state before they change a durable Room process. Startup-only declarations keep their current in-memory behavior.
- **R6:** Deprovisioning stops the managed Room and deletes only its declaration. It preserves the Room record, memberships, and history.
- **R7:** A durable membership stores one portable member identity, status, revision, issuer, metadata, and lifecycle timestamps. Active, suspended, and revoked are valid statuses.
- **R8:** Membership transitions use an expected revision. Repeated join and leave requests are idempotent. Authorization reads active durable membership when Room durability is enabled.
- **R9:** Durable message history stores immutable committed Room message Signals with stable Room sequence numbers. A repeated message ID returns the stored value, and different content for the same ID fails.
- **R10:** Message history queries have stable oldest-first order and bounded `before`, `after`, `thread_id`, and `limit` options.
- **R11:** A durable Room Agent restores active members, recent messages, and the last sequence before Jido starts it. Its local state remains a bounded working cache.
- **R12:** Memory and DETS implement the same declarations, memberships, history, and Commit contracts. DETS writes format 4 with separate history records and reads and migrates formats 1 through 3.
- **R13:** The contracts are framework-neutral. A host can implement them with Ecto, Ash resources, or another store. Jido Chat adds no package.

### Acceptance Examples

1. `provision_room("team", %{id: "support", kind: :group})` writes one Room record and one running declaration. A later Runtime start creates the registered Room Agent.
2. A stored definition key that is not in the host registry reports `:unknown_room_definition`. It never creates an atom.
3. `stop_managed_room/1` changes a durable declaration to `:stopped`. After a Runtime restart, the Room stays stopped.
4. A startup declaration and a durable declaration with the same Room ID fail as an explicit duplicate instead of selecting one silently.
5. `deprovision_room/1` stops the Room and removes the declaration. `get_room/1`, membership queries, and message history still return their data.
6. A join survives a Room process restart. A leave changes the durable membership to revoked and removes it from the restored active member cache.
7. A post survives a Room process restart. Repeating the same post after it falls outside the working cache returns the original committed Signal without adding a second history record.
8. History pagination returns stable sequence order. It rejects both `before` and `after` in one query and limits results to 1 through 1,000.
9. A failed batch that contains a Room record and a conflicting declaration changes no storage state.
10. A format-2 DETS snapshot opens with its existing Room records and empty declarations, memberships, and history. A format-3 snapshot moves its history into separate format-4 records.

### Scope Boundaries

In scope:

- Durable Room declarations and desired state.
- Room provisioning and safe deprovisioning.
- Durable Room memberships and immutable message history.
- Managed Room hydration and storage-backed Room commands.
- Runtime facade queries.
- Memory, DETS, Engine, Commit, tests, and adapter documentation.

Out of scope:

- Durable provider connection declarations or stored credentials.
- Message edit, delete, reaction, receipt, search, and retention jobs.
- Provider binding records or old `jido_messaging` data import.
- Ecto or Ash implementations, database migrations, and cluster transactions.
- Automatic deletion of Room records, memberships, or history.
- UI and `jido_assembly` changes.

### Key Decisions

- The Runtime module is the trusted composition root. It owns the definition registry and storage selection.
- A durable Room definition opts into storage by naming its Runtime module in the Room DSL. The module reference stays in trusted compiled code.
- Storage is authoritative for durable membership and history. Room Agent state is a bounded cache used for local turns and delivery.
- A Room command writes storage before Agent commit. If the later Agent checkpoint fails, an idempotent retry and the next activation converge from storage.
- Provisioning data is atomic. Durable acceptance and live process activation are separate results because storage and Jido do not share one transaction.
- Provider connections remain startup-only. Their definitions can contain credentials and need a separate secret-reference design.

## Planning Contract

### Current System

`Jido.Chat.Runtime.Manager` reconciles startup Room and provider-account declarations. `Room.Plugin` owns an in-memory member list, a bounded Signal list, and a sequence. Runtime storage supplies Links, Outbox, Rooms, and Commit capabilities through a pure Engine. Memory and DETS use that Engine. DETS format 2 can read format 1.

### Target System

The host Runtime supplies `room_definitions: %{"team" => MyApp.TeamRoom}`. A durable declaration refers to `"team"`. The manager merges startup declarations with stored declarations, rejects duplicate IDs, resolves trusted definitions, hydrates stored Room working state, and asks Jido to start or stop Agents.

A durable Room definition sets `runtime(MyApp.Chat)` in its `room` block. The Plugin uses that Runtime only for storage operations. Direct Rooms with no Runtime keep the present in-memory behavior.

### Failure Semantics

- Missing storage returns `:room_storage_required`.
- A missing capability returns `:unsupported_storage_capability`.
- An unknown stored definition key returns `:unknown_room_definition`.
- A revision mismatch returns a domain conflict and leaves storage unchanged.
- A stored command followed by Agent checkpoint failure can leave storage ahead of the local cache. Retry and activation are safe because member transitions and message IDs are idempotent.
- A live activation failure does not roll back accepted provisioning data. Status reports the activation error and later reconciliation retries it.

### Implementation Units

#### U1: Durable declarations and registry

- Add `Room.Declaration` and `Storage.RoomDeclarations`.
- Add declaration commands and queries to Engine, Memory, DETS, Adapter, and Commit.
- Add the `room_definitions` Runtime option and safe resolver.
- Upgrade DETS format to 4, expand old snapshots, and move format-3 history into separate records.
- Test validation, conflicts, revision transitions, and old-format restoration.

#### U2: Provisioning and managed reconciliation

- Add a provisioning service and Runtime facade functions.
- Commit Room record plus declaration atomically.
- Load and merge durable declarations in Manager.
- Persist durable desired-state changes before reconciliation.
- Add safe deprovisioning that preserves Room data.
- Test restart recovery, duplicate ID handling, unknown keys, activation failure, and no cascade.

#### U3: Membership and history contracts

- Add portable Membership and History record modules.
- Add `Memberships` and `History` storage capabilities.
- Add Engine indexes, deterministic queries, revision checks, idempotency, Commit support, and Memory and DETS callbacks.
- Add Runtime facade membership and history queries.
- Test string and Agent Address members, status transitions, cursor rules, thread filters, message conflicts, atomic rollback, and DETS restart.

#### U4: Room durability and recovery

- Add an optional Runtime setting to `Room.Plugin`.
- Use active durable memberships for authorization.
- Persist join, leave, and post operations before Agent commit.
- Return a stored Signal for a repeated post ID.
- Hydrate active members, recent history, and last sequence before managed Room activation.
- Keep local history and member limits unchanged.
- Test Room stop/start recovery, bounded cache versus full history, authorization after leave, and idempotency outside the cache.

### Verification

Run focused record, storage, manager, and Room tests after each unit. Then run:

```text
mix test
mix quality
mix xref graph --format cycles
mix docs
```

Use an independent verifier for the final diff. Check production code, tests, documentation, storage migration behavior, authorization behavior, and process ownership. Success requires all package tests and quality checks to pass, no dependency change, no process tree outside the optional Runtime, and no stored executable module or credential value.

### Sources

- Direct user request on 2026-11-16.
- `lib/jido_chat/runtime.ex`
- `lib/jido_chat/runtime/{manager,supervisor,room}.ex`
- `lib/jido_chat/runtime/room/{plugin,record,records}.ex`
- `lib/jido_chat/runtime/storage/{adapter,engine,memory,dets,commit}.ex`
- `test/jido_chat/{runtime_manager,runtime_room,runtime_storage,runtime_storage_dets}_test.exs`
- Local `jido_messaging` Message, Membership, persistence, and RoomServer source as behavior evidence only.
