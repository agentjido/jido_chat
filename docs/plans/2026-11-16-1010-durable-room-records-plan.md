---
title: Add durable room records and queries
type: implementation-plan
date: 2026-11-16
last_reviewed: 2026-11-16
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Add durable room records and queries

## Goal Capsule

- Objective: Let a host create, read, query, update, and delete durable Chat Room records through its Runtime facade.
- Means: Add one portable Room record, one adapter-neutral Rooms storage capability, built-in Memory and DETS implementations, and facade query functions.
- Authority: Local writes in `jido_chat`. Preserve the current managed Runtime changes. Do not commit, push, publish, release, or change a sibling package.
- Stop conditions: Stop if the change needs Ecto, Ash, another package, a Jido Core change, an old `jido_messaging` data migration, or a destructive automatic conversion.
- Next executor: Jido Chat implementer and independent verifier.

## Product Contract

### Summary

Jido Chat stores durable Room identity and descriptive metadata behind a small storage capability. Hosts can use the built-in local adapters or implement the same contract with Ecto, Ash resources, or another storage system.

### Problem Frame

The managed Runtime can start and reconcile declared Room Agents, but it has no durable Room catalog. A host cannot create a stable Room record, fetch it after restart, query stored rooms, or change metadata with conflict protection. A previous broad Rooms capability was removed because no Runtime process used it and because it mixed room definitions with membership. The managed Runtime now gives the feature a caller and lifecycle boundary.

### Actors

- A host application that uses its Runtime facade to manage Room records.
- A storage adapter author who maps the Rooms capability to Memory, DETS, Ecto, Ash, or another store.
- An operator who restarts the storage process and expects accepted Room records to remain available.

### Requirements

- **R1:** Jido Chat provides one validated, portable, versioned Room record with stable identity, kind, optional name, public metadata, record revision, and timestamps.
- **R2:** The Rooms capability supports insert, get, deterministic list, revision-checked update, and revision-checked delete operations.
- **R3:** Room list queries support an optional Room kind, an exclusive Room-ID cursor, and a bounded limit. Results use stable oldest-first order by insertion time and ID.
- **R4:** Concurrent updates and deletes fail with a revision conflict instead of silently replacing a newer Room record.
- **R5:** Memory implements Rooms with the same pure Engine invariants as other built-in storage capabilities. Commit can include Room operations and remains all-or-none.
- **R6:** DETS retains Room records across restart and safely reads format-version 1 snapshots by expanding them with an empty Room map. Unsupported versions still fail closed.
- **R7:** A Runtime facade exposes create, get, list, update, and delete functions and returns clear errors when no Rooms-capable storage is configured.
- **R8:** Durable Room records remain separate from live managed Room Agent status. The existing managed Room list gets an explicit managed name.
- **R9:** The public storage contract remains framework-neutral and adds no package dependency.

### Key Flows

```text
Runtime facade
  -> validate Room input or query
  -> validate Rooms storage capability
  -> adapter operation on host-owned resource
  -> durable Room.Record result
```

```text
update or delete
  -> read current record
  -> build next valid record when needed
  -> compare expected revision in the adapter transaction
  -> accept or return revision conflict
```

### Acceptance Examples

1. `MyApp.Chat.create_room(%{kind: :group, name: "Support"})` returns a Room record with a generated stable ID, revision 1, and UTC timestamps.
2. `get_room/1` returns the same record. A missing Room returns `{:error, :not_found}`.
3. `list_rooms/1` filters by kind, applies a limit from 1 through 1,000, and continues after the Room named by `:after` without duplicates.
4. Updating a Room with its current revision changes only name or metadata, increments the revision, and keeps the insertion time. A stale revision returns `{:error, :room_conflict}`.
5. Deleting a Room with its current revision removes only the Room record. It does not stop a Room Agent or delete membership, message, Bus, or provider data.
6. A DETS restart returns the same Room record and query order.
7. A version-1 DETS snapshot with Links or Outbox data opens with an empty Room catalog and preserves its existing data.
8. A Runtime without storage, or with storage that lacks Rooms, returns a capability error and does not start a hidden resource.
9. `list_managed_rooms/0` continues to report live managed Agent status. `list_rooms/1` reports durable Room records.

### Success Criteria

- Public Room record and facade behavior pass focused tests.
- Memory and DETS pass the same Room storage invariants.
- Format-version 1 DETS data remains readable.
- Existing managed Runtime, Bridge storage, contract, and package tests pass.
- Static quality checks pass.

### Scope Boundaries

In scope:

- Durable Room identity and metadata records.
- Create, get, list, update, and delete queries.
- Revision conflict protection.
- Memory, DETS, Engine, Commit, and adapter documentation.
- The Runtime facade and the managed Room list rename.

Out of scope:

- Room membership persistence.
- Durable message history or Bus storage.
- Room bindings to provider channels.
- Automatic Room Agent creation, start, stop, or deletion from a Room record.
- A durable managed-Runtime declaration catalog.
- Ecto schemas, Ash resources, database migrations, tenancy, or cluster coordination.
- Import of old `jido_messaging` Room records.
- Soft deletion, retention policy, or record restoration.

### Key Decisions

- A Room record is descriptive domain data. It is not a live Agent snapshot or desired-state declaration.
- Room kinds are `:direct`, `:group`, `:channel`, and `:thread`.
- Kind, ID, insertion time, and schema version are immutable after insert. Update can change only name and metadata.
- Record deletion is explicit and revision checked. It does not cascade.
- List order is insertion time ascending, then ID ascending. `:after` names an existing Room ID and is exclusive.
- The default list limit is 100. The maximum is 1,000.

### Rejected Alternatives

- Restore the removed Room-plus-membership map capability unchanged: rejected because Room membership remains Room Agent state and the old contract had no list or concurrency rules.
- Store Room records in Jido Agent checkpoints only: rejected because catalog queries and metadata lifecycle are not Agent activation state.
- Make the managed Runtime declarations the durable record: rejected because an Agent definition and desired process state are different from a Room domain record.
- Add Ecto or Ash directly: rejected because the host owns its persistence framework.
- Delete a live Agent or related data when a record is deleted: rejected because this slice has no authorized cascade or retention policy.

### Dependencies

- The existing `{adapter, resource}` Runtime storage selection.
- The existing shared storage Engine, Memory adapter, DETS adapter, Adapter declaration, and Commit capability.
- The current managed Runtime facade candidate, which already uses `list_rooms/0` for live status.
- Consolidated Jido `Jido.Id.uuid7/0` for generated record identity.

### Outstanding Questions

None. Bindings, membership, history, automatic Agent lifecycle, and old-data import are explicit later features.

### Sources

- Direct user request on 2026-11-16.
- `lib/jido_chat/runtime.ex`
- `lib/jido_chat/runtime/storage.ex`
- `lib/jido_chat/runtime/storage/{adapter,engine,memory,dets,commit}.ex`
- `test/jido_chat/{runtime_storage,runtime_storage_dets,runtime_manager}_test.exs`
- `guides/{architecture,runtime,storage_adapters}.md`
- Historical `Jido.Chat.Room` and removed `Storage.Rooms` source in local Git history.
- `jido_messaging` room CRUD and persistence source as behavior evidence only.

## Planning Contract

### Product Contract Preservation

Product Contract unchanged.

### Current System

`Jido.Chat.Runtime.Storage` validates small adapter capabilities. Memory and DETS implement Links, Outbox, and Commit through one pure Engine. DETS stores a version-1 snapshot. There is no current Room record type or Rooms capability. Room membership and bounded working history live in `Jido.Chat.Runtime.Room.Plugin`. The current managed Runtime candidate stores only startup declarations and live status in its manager.

The old `jido_messaging` API provided create, get, list, and delete Room operations, but its persistence behavior mixed many unrelated records and its RoomServer duplicated Agent ownership. The earlier V3 storage work temporarily added a generic Room map plus membership capability. The design review removed it because no owner used it.

### Target System

`Jido.Chat.Runtime.Room.Record` is the only durable Room catalog value. It has this meaning:

```text
schema_version: 1
id: nonempty string, maximum 256 bytes
kind: direct | group | channel | thread
name: optional string, maximum 256 bytes
metadata: portable map
revision: positive integer
inserted_at: UTC DateTime
updated_at: UTC DateTime
```

`Jido.Chat.Runtime.Storage.Rooms` is a separate adapter capability. Built-in adapters store validated Record structs. A Runtime facade uses a small Room records service to validate storage, construct records, apply revision checks, and map missing storage values to public errors.

### Key Technical Decisions

#### KTD1: Store one narrow Room catalog record

- **Decision:** Add `Jido.Chat.Runtime.Room.Record`; do not store membership, history, live PID, desired process state, Agent state, credentials, or provider bindings in it.
- **Reason:** R1, R8, and R9 need a durable domain record without duplicating current owners.
- **Rejected alternative:** Reuse the Room Agent Plugin state as the catalog. That state is activation data and does not supply adapter-neutral catalog queries.
- **Consequences:** A Room record and a Room Agent can exist independently. A later catalog-to-runtime feature can connect them explicitly.
- **Governs:** R1, R7, R8, U1, U3.

#### KTD2: Use revision-checked domain operations

- **Decision:** Rooms exposes insert, get, list, update with expected revision, and delete with expected revision. Updates can change only name and metadata.
- **Reason:** R2 and R4 need complete record lifecycle without lost updates.
- **Rejected alternative:** One unconstrained `put_room/2`. It cannot distinguish create from overwrite and cannot reject stale callers.
- **Consequences:** Custom Ecto and Ash adapters need an atomic revision condition for update and delete.
- **Governs:** R2, R4, R5, U1, U2, U3.

#### KTD3: Define deterministic bounded queries

- **Decision:** List uses `kind:`, `after:`, and `limit:`. Results sort by insertion time and ID. The cursor is an existing Room ID.
- **Reason:** R3 requires repeatable pagination that Memory, DETS, Ecto, and Ash can implement.
- **Rejected alternative:** Return all records in map or database order. This is unstable and unbounded.
- **Consequences:** Deleting the cursor record makes a later query return `:invalid_room_cursor`. Hosts that need opaque, stable cursors can add a later query contract.
- **Governs:** R3, U1, U2, U3.

#### KTD4: Expand DETS format with an explicit version-1 reader

- **Decision:** Write format version 2. Read version 1 by validating its Links and Outbox Engine fields and adding an empty Room map. Keep unknown versions closed.
- **Reason:** R6 adds stored meaning and must not discard accepted version-1 data.
- **Rejected alternative:** Keep format version 1 or reject all old snapshots. The first hides a schema change; the second breaks existing durable users.
- **Consequences:** Rollback to code that only reads version 1 is unsafe after the first version-2 write. Operators must back up a DETS file before upgrade if rollback is required.
- **Governs:** R6, U2.

#### KTD5: Keep durable and managed Room queries separate

- **Decision:** Rename live status `list_rooms/0` to `list_managed_rooms/0`. Use `list_rooms/1` with a default empty query for durable records.
- **Reason:** R7 and R8 require clear ownership at the public facade.
- **Rejected alternative:** Overload one result shape by process state. A caller could confuse durable catalog data with live Agent status.
- **Consequences:** This adjusts only the current uncommitted managed Runtime candidate. No released API is removed.
- **Governs:** R7, R8, U3.

### System Boundaries and Change Surface

| Surface | Current contract | Planned change | Compatibility or risk |
| --- | --- | --- | --- |
| Room value | No durable Runtime Room value | Add versioned `Room.Record` with portable map conversion | New additive public value |
| Rooms storage | No current capability | Add domain CRUD and list callbacks | Custom adapters opt in |
| Engine | Links and work maps | Add validated Room map, revision checks, queries, and Commit commands | Pure state transition remains atomic |
| Memory | Links, Outbox, Commit | Add Rooms callbacks | Existing configuration stays valid |
| DETS | Snapshot format 1 | Write 2; read and expand 1 | Forward migration; old-code rollback limit |
| Runtime facade | Direct connection and managed Agent functions | Add Room record CRUD/query functions | No hidden storage startup |
| Managed Runtime | `list_rooms/0` returns live status | Rename to `list_managed_rooms/0` | Uncommitted surface only |
| Room Agent | Membership and working history | No change | Durable record deletion has no Agent effect |
| Adapter guide | Links, Outbox, Commit mappings | Add Room schema/resource and query rules | No Ecto or Ash dependency |

Room storage errors:

- `:room_storage_required` when the Runtime has no storage selection.
- `:unsupported_storage_capability` when the selected adapter lacks Rooms.
- `:not_found` for a missing Room at the facade.
- `:room_conflict` for duplicate insert or stale update/delete.
- `:invalid_room_cursor`, `:invalid_room_kind`, `:invalid_limit`, or `:invalid_options` for bad queries.

### Implementation Units

#### U1: Room record and storage invariants

- **Outcome:** One portable Room record and one Rooms capability have complete create, query, revision, and delete semantics in the pure Engine and Memory.
- **Requirements:** R1-R5, R9.
- **Dependencies:** None.
- **Affected surfaces:** New `runtime/room/record.ex`, new `runtime/storage/rooms.ex`, storage Adapter, Commit, Engine, Memory, and focused storage tests.
- **Implementation direction:** Normalize atom and string input keys. Generate a `room/` UUID7 ID when absent. Validate UTC timestamps and portable metadata. Insert is idempotent only for the same complete record. Update and delete compare the expected revision. Query options are closed and bounded.
- **Test scenarios:** Valid record and map round trip; invalid kind, metadata, ID, and timestamp; duplicate insert; get; kind filter; cursor and limit; stable order; stale update and delete; immutable fields; Commit rollback.
- **Verification:** Run Room record and Runtime storage focused tests.
- **Completion signal:** Memory returns the documented records and errors, and a failed Commit changes no Room state.

#### U2: Durable DETS format expansion

- **Outcome:** Room records and queries survive DETS restart, and version-1 snapshots open without loss.
- **Requirements:** R5, R6, R9.
- **Dependencies:** U1.
- **Affected surfaces:** `runtime/storage/dets.ex`, Engine restoration, and DETS tests.
- **Implementation direction:** Set the writer format to 2. Keep the same DETS key. Add a narrow version-1 load path that validates old fields and supplies `rooms: %{}`. Persist version 2 on the next accepted change. Do not reset an invalid or unknown file.
- **Test scenarios:** Room round trip after restart; list filter and cursor after restart; atomic Commit rollback; version-1 Links and Outbox preservation; unknown version rejection.
- **Verification:** Run the DETS test file against fresh temporary paths.
- **Completion signal:** Version-2 Room records and migrated version-1 data are readable after restart.

#### U3: Runtime facade and adapter documentation

- **Outcome:** Hosts can use durable Room CRUD and queries from their Runtime facade, while managed Agent status stays separate.
- **Requirements:** R7-R9.
- **Dependencies:** U1, U2.
- **Affected surfaces:** New Room records service, `runtime.ex`, managed Runtime tests and guide, storage adapter guide, architecture, source layout, README, and changelog.
- **Implementation direction:** Validate the Rooms capability before each facade operation. Add both convenience update/delete functions and explicit revision forms. Rename the uncommitted live list function. Document that record deletion does not cascade or stop Agents.
- **Test scenarios:** Facade create/get/list/update/delete; no storage; unsupported adapter; stale revision; live managed list still works; no automatic Agent action.
- **Verification:** Run focused Runtime manager and storage tests, then full package gates.
- **Completion signal:** The facade examples work with Memory and DETS, and the managed status API has one unambiguous name.

### Work Graph

- Initial frontier: U1.
- Critical path: U1 -> U2 -> U3.
- Parallel work: Documentation can start after U1, but final examples wait for U3 names.
- Final integration unit: U3.

### Verification Contract

| Gate | Applies to | Evidence | Done signal |
| --- | --- | --- | --- |
| Room value | U1 | Focused Room record tests | Validation and portable round trip pass |
| Memory behavior | U1 | Runtime storage tests | CRUD, queries, revision checks, and Commit rollback pass |
| Durable migration | U2 | DETS tests | Version 2 restarts and version 1 expands without data loss |
| Runtime integration | U3 | Facade and managed Runtime tests | Durable and live Room APIs stay separate |
| Contracts | U3 | Covenant checks | Active public obligations pass |
| Repository | U1-U3 | Full tests and `mix quality` | No regression or static failure |
| Design review | U3 | Independent source review | No duplicated Room owner, unsafe overwrite, or hidden cascade remains |

Run from `/Users/mhostetler/Source/Jido/jido_chat/jido_chat`:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test test/jido_chat/runtime_room_record_test.exs
mix test test/jido_chat/runtime_storage_test.exs test/jido_chat/runtime_storage_dets_test.exs
mix test test/jido_chat/runtime_manager_test.exs test/jido_chat/runtime_room_test.exs
mix test.contracts
mix test
mix quality
mix xref graph --label compile-connected --format cycles
git diff --check
git status --short
```

Requirement traceability:

| Requirement | Units | Verification |
| --- | --- | --- |
| R1 | U1 | Room value tests |
| R2 | U1, U3 | Memory and facade CRUD tests |
| R3 | U1-U3 | Memory, DETS, and facade query tests |
| R4 | U1, U3 | Stale update and delete tests |
| R5 | U1, U2 | Commit rollback tests |
| R6 | U2 | DETS restart and version-1 migration tests |
| R7 | U3 | Facade capability and error tests |
| R8 | U3 | Managed status and no-cascade tests |
| R9 | U1-U3 | Adapter validation, docs, dependency, and package checks |

### Rollout and Recovery

This is additive except for the DETS writer format. Back up a DETS file while its adapter is stopped before first version-2 use when rollback is required. New code reads versions 1 and 2. Old code reads only version 1, so do not roll old code back after a version-2 write. An invalid or unknown version stops startup and preserves the file. Memory users need no migration. Custom adapters opt in to Rooms when ready.

### Risks and Assumptions

- Risk: A lost update replaces newer metadata. Prevention: atomic expected-revision checks in update and delete.
- Risk: Pagination changes while records are inserted or deleted. Detection: stable order and cursor tests. Limit: this contract is not a snapshot query.
- Risk: A Room record delete is mistaken for Room teardown. Prevention: separate function names, no cascade, and documented live-status APIs.
- Risk: Version-2 DETS writes prevent old-code rollback. Recovery: restore the pre-upgrade backup or forward-recover with version-2 code.
- Risk: Custom adapters implement unstable ordering. Prevention: the callback documentation and conformance cases define the sort and cursor rules.
- Assumption: Room metadata is public Chat domain metadata and contains no credentials. The portable-value check rejects process-local and non-JSON data, but the host remains responsible for data classification.

### Open Planning Decisions

None. Membership, history, bindings, durable managed declarations, soft delete, and old-data import are deferred.

### Definition of Done

- R1-R9 have implementation and current evidence.
- The Room record is validated, portable, and versioned.
- Memory and DETS enforce the same Room lifecycle, query, revision, and Commit rules.
- Version-1 DETS data remains readable and unchanged in meaning.
- Runtime facade Room CRUD is usable without confusing durable records with live Agent status.
- Room record deletion has no hidden cascade.
- Ecto and Ash need no dependency or branch in Jido Chat.
- Focused tests, full tests, contracts, formatting, compilation, quality, Xref, and independent review pass.
- No commit, push, release, package publication, live migration, or sibling change occurs.

### Planning Sources

- Repository source and tests at local HEAD `cfce0256b468bcf14819a18a9ded7c58765213f9` plus the current managed Runtime worktree candidate.
- Historical durable storage commit `0490a7b` and design-review commit `cfce025`.
- Local `jido_messaging` room CRUD and adapter source as feature evidence, not as target architecture.
- Jido kata planning, work, and verification methods selected by the user.

## Adapter Results

- Markdown: canonical at `docs/plans/2026-11-16-1010-durable-room-records-plan.md`
- HTML: not requested
- Beadwork: not requested
