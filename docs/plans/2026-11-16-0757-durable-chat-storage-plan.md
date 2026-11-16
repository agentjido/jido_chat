---
title: Durable adapter-neutral Chat storage
type: implementation-plan
date: 2026-11-16
last_reviewed: 2026-11-16
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Durable adapter-neutral Chat storage

## Goal Capsule

- Objective: Let Jido Chat retain Runtime rooms, history, bridge links, and provider work across storage-process and VM restarts without coupling Chat to one persistence framework.
- Means: Keep the existing capability behaviors as the public boundary, add a common adapter declaration, add a dependency-free DETS reference adapter, and make provider-work claims recoverable through durable leases.
- Authority: Local product code, tests, plan, and guides in `jido_chat`. No commit, push, package publication, sibling-repository change, or live migration.
- Stop conditions: Stop if the implementation requires Ecto, Ash, a database credential, a new package, a change to Jido Core, or a destructive migration.
- Next executor: Jido Chat implementer and verifier.

## Product Contract

### Summary

Jido Chat supplies durable Runtime storage without selecting a host persistence framework. A host can use the built-in local DETS adapter or implement the same small capability contracts with an Ecto Repo, Ash resources, an event store, or another durable service.

### Problem Frame

The Runtime already separates History, Links, Outbox, Rooms, and Commit capabilities, but its only implementation is process-local Memory storage. The bridge can persist work through an adapter, yet a claimed item has no implemented lease and can remain stranded after a worker restart. The host needs one usable durable adapter and one clear extension contract that does not add Ecto or Ash to Jido Chat.

### Actors

- A host application that starts and owns a Chat storage resource.
- A storage adapter author who uses Ecto, Ash, or another persistence system.
- A Room or Bridge Runtime that reads and writes Chat domain records.
- An operator who restarts a Chat process and expects accepted records and recoverable work to remain available.

### Requirements

- **R1:** Jido Chat provides a durable reference adapter that survives storage-process restart and uses no new package dependency.
- **R2:** Storage remains selected as `{adapter_module, resource}` and the host owns resource startup and lifetime.
- **R3:** An adapter declares any subset of History, Links, Outbox, Rooms, and Commit and is validated against the callbacks it claims.
- **R4:** Ecto and Ash integrations can implement the public storage contract without a compile-time dependency from Jido Chat to either framework.
- **R5:** A Commit applies all commands or none at the adapter transaction boundary.
- **R6:** Provider work claims carry a durable owner and expiry. Recovery requeues only expired, inactive claims and never automatically resubmits submitted or terminal work.
- **R7:** Stored snapshots have an explicit format version. Unsupported versions fail closed instead of being reset or overwritten.
- **R8:** The Memory adapter and all current Runtime callers remain compatible.

### Key Flows

```text
Room or Bridge
  -> capability callback on adapter module
  -> host-owned resource
  -> adapter transaction or serialized durable write
  -> typed Chat result

Bridge recovery
  -> list pending and claimed work
  -> reclaim only expired inactive claims
  -> claim with owner and expiry
  -> mark submitted before provider effect
  -> complete, fail, or record unknown outcome
```

### Acceptance Examples

- A message, room, membership list, link, and outbox item remain readable after the DETS storage process stops and starts with the same path.
- A failed multi-command Commit leaves no partial room or work record.
- An adapter that declares History but omits a History callback fails storage validation.
- A direct adapter can use an Ecto Repo as its resource and map Commit to `Repo.transact/2`.
- A direct adapter can use Ash resources as its resource and map Commit to `Ash.transact/3`.
- An expired claimed provider item returns to pending and executes after recovery.
- A live claim, submitted item, failed item, unknown item, or completed item is not automatically requeued.
- A DETS file with an unsupported snapshot version does not start as an empty store.

### Success Criteria

Focused storage and Bridge recovery tests pass. The full test suite, public contract suite, formatter, warnings-as-errors compilation, Credo, Dialyzer, and Doctor pass.

### Scope Boundaries

In scope: adapter declaration and validation, shared in-process storage engine, DETS durability, snapshot version checks, provider-work leases, recovery tests, public guides, and source-layout documentation.

Out of scope: an Ecto schema, Ash resources, SQL migrations, old `jido_messaging` data migration, multi-node consensus, automatic retry after provider submission, database credentials, and Assembly migration.

### Key Decisions

- Capability behaviors remain the framework-neutral public contract.
- Jido Chat has no Ecto or Ash dependency.
- DETS is a local, single-node reference adapter. It is not presented as a distributed production database.
- Ecto and Ash adapter authors own their schemas, migrations, tenant rules, and framework-specific transactions.
- Existing persisted `jido_messaging` records are not read or converted.

### Rejected Alternatives

- Add Ecto and Ash to Jido Chat. This increases the core dependency graph and selects frameworks for the host.
- Define one generic CRUD callback set. This hides domain invariants and makes atomic bridge operations harder to prove.
- Persist only Agent checkpoints. Chat history and provider work have different query and recovery contracts.
- Copy the old `Jido.Messaging.Persistence` behavior. It joins unrelated application, identity, projection, and runtime concerns.

### Dependencies

Erlang/OTP DETS is available without a new Hex dependency. Ecto and Ash are host choices. Current official framework APIs both provide transaction entry points, but adapters must use the version selected by their host.

### Outstanding Questions

None blocking. A later unit can add first-party SQL or Ash adapters without changing the capability contracts.

### Sources

- `lib/jido_chat/runtime/storage.ex`
- `lib/jido_chat/runtime/storage/{history,links,outbox,rooms,commit,memory}.ex`
- `lib/jido_chat/runtime/bridge/worker.ex`
- `test/jido_chat/runtime_storage_test.exs`
- `test/jido_chat/runtime_bridge_test.exs`
- `guides/architecture.md`
- Ecto Repo transaction API: https://ecto.hexdocs.pm/Ecto.Repo.html
- Ash transaction API: https://ash.hexdocs.pm/Ash.html#transact/3

## Planning Contract

### Product Contract Preservation

Product Contract unchanged.

### Current System

`Jido.Chat.Runtime.Storage` accepts `{adapter, resource}` and detects a capability by checking its behavior callbacks. `Memory` implements all five capabilities in one GenServer and applies Commit commands against an immutable candidate state before it accepts the new state. Runtime Bridge work uses pending, claimed, submitted, completed, failed, and unknown states. The Memory implementation permits lease fields, but the worker does not create or recover durable leases. Only pending work is scheduled during recovery.

### Target System

`Jido.Chat.Runtime.Storage.Adapter` gives adapter authors one declaration for the capabilities they implement. `Storage.validate/2` checks both the declaration and exported callbacks while retaining compatibility with existing callback-only adapters. A private shared storage engine owns validation, commands, queries, and atomic candidate-state application for built-in adapters.

`Jido.Chat.Runtime.Storage.Dets` serializes access through a host-owned GenServer. It stores one versioned Runtime snapshot per DETS table. Each accepted command or Commit produces a new candidate state and one synchronized snapshot write. Restart loads the last supported snapshot. An unknown version stops startup.

An Ecto or Ash adapter does not use the DETS engine. It implements the same capability callbacks against its host resource and uses its framework transaction for Commit.

### Key Technical Decisions

#### KTD1: Keep domain capabilities as the adapter port

- Decision: Add an adapter declaration over the existing History, Links, Outbox, Rooms, and Commit behaviors. Do not replace them with generic CRUD.
- Reason: R2-R5 require framework independence and domain-specific atomicity.
- Rejected alternative: A universal record-store behavior. It would leak query and transaction policy back into Runtime.
- Consequences: Ecto and Ash adapters have the same public callbacks but can model their own records and indexes.
- Governs: R2, R3, R4, R5, U1, U4.

#### KTD2: Use a dependency-free local durable reference

- Decision: Add a host-owned DETS adapter that stores one versioned snapshot.
- Reason: R1 needs executable durability now without selecting Ecto, Ash, or SQL.
- Rejected alternative: Add Exqlite directly. It would add a new runtime dependency and still not prove framework neutrality.
- Consequences: The built-in adapter is suitable for local and single-node use. Large or distributed systems use a custom adapter.
- Governs: R1, R5, R7, U2.

#### KTD3: Share invariants, not persistence mechanics

- Decision: Extract the current Memory command and query rules into one internal pure engine used by Memory and DETS.
- Reason: The two built-in adapters must return the same results and reject the same invalid transitions.
- Rejected alternative: Duplicate Memory logic in DETS. It would allow behavior drift.
- Consequences: Direct Ecto and Ash adapters remain free to implement efficient queries but use the same public conformance cases.
- Governs: R1, R5, R8, U1, U2.

#### KTD4: Persist bounded provider-work leases

- Decision: Add a configurable lease duration. A claim records a stable worker owner and UTC expiry. Recovery moves only expired claims back to pending.
- Reason: Durable storage is unsafe if a worker crash can strand a claimed item forever.
- Rejected alternative: Requeue every claimed item at startup. This can duplicate a still-active provider request.
- Consequences: Recovery can wait for lease expiry. Submitted and terminal work remains operator-controlled.
- Governs: R6, U3.

### System Boundaries and Change Surface

| Surface | Current contract | Planned change | Compatibility or risk |
| --- | --- | --- | --- |
| Storage selection | `{adapter, resource}` | Unchanged | Existing Runtime configuration remains valid |
| Capability validation | Exported callbacks only | Optional explicit adapter declaration plus callback validation | Callback-only third-party adapters remain accepted |
| Memory | Own command rules and state | Delegate to shared pure engine | Public functions and errors remain stable |
| Durable reference | None | Add host-owned `Storage.Dets` | Single-node and local; no hidden application process |
| Stored format | None | Versioned DETS snapshot | Unsupported version stops startup |
| Provider work | Claim has no active lease | Claim owner and expiry plus expired-claim recovery | Submitted and terminal work is never retried automatically |
| Runtime options | Work and queue limits | Add positive `provider_work_lease_ms` | Existing definitions use the default |
| Custom frameworks | Undocumented direct behaviors | Document Ecto Repo and Ash resource mappings | No framework compile dependency |

### Implementation Units

#### U1: Adapter declaration and shared storage engine

- Outcome: Memory and future built-in adapters use one invariant implementation, and custom adapters can declare supported capabilities.
- Requirements: R2, R3, R4, R5, R8.
- Dependencies: None.
- Affected surfaces: `runtime/storage.ex`, new adapter and engine modules, `runtime/storage/memory.ex`, focused storage tests.
- Implementation direction: Keep all current callback signatures and error atoms. Make capability declarations additive. Validate declarations against actual callbacks. Move command and query state changes into an internal pure module.
- Test scenarios: complete declaration, partial declaration, declared-but-missing callback, callback-only compatibility, Memory regression, and Commit rollback.
- Verification: Run the focused Runtime storage test.
- Completion signal: Memory passes its existing tests through the shared engine and capability validation rejects a false declaration.

#### U2: Durable DETS adapter

- Outcome: One host-owned local adapter retains every Runtime capability across process restart.
- Requirements: R1, R2, R5, R7, R8.
- Dependencies: U1.
- Affected surfaces: new DETS adapter, storage tests, Runtime guide.
- Implementation direction: Require an explicit DETS table atom and path. Store one `{snapshot, format_version, state}` record. Synchronize each accepted state. Close the table on normal termination. Reject invalid or unknown snapshots without truncating the file.
- Test scenarios: full capability round trip, process restart, idempotent message append, failed Commit rollback, and unknown format rejection.
- Verification: Run the DETS-focused tests twice against fresh temporary files.
- Completion signal: The same records are returned after adapter restart and no failed Commit is visible.

#### U3: Durable provider-work claims

- Outcome: A Bridge restart can recover an expired claim without duplicating live or submitted work.
- Requirements: R6, R8.
- Dependencies: U1.
- Affected surfaces: Runtime configuration, Connection binding, Bridge normalization, Bridge Worker, Outbox tests, Bridge integration tests.
- Implementation direction: Default the lease to a bounded positive duration. Store an opaque owner string and system-time expiry when pending work becomes claimed. Clear lease data when leaving claimed. Recovery first reclaims expired inactive claims and then schedules pending work.
- Test scenarios: expired claim recovers, live claim stays claimed, old claim without lease recovers, submitted and terminal records stay unchanged, and current pending recovery still passes.
- Verification: Run Runtime storage and Bridge tests.
- Completion signal: Recovery test observes one provider execution for the expired claim and none for protected states.

#### U4: Adapter author contract and repository integration

- Outcome: An Ecto or Ash adapter author can implement the contract without reading Runtime internals, and all repository gates pass.
- Requirements: R3, R4, R8.
- Dependencies: U2, U3.
- Affected surfaces: new storage-adapter guide, Runtime and source-layout guides, docs extras, public API wording, contract fixtures if required.
- Implementation direction: Document capability-by-capability records, resource ownership, transaction expectations, error rules, and framework mappings. State that Commit may be declared only when one backing transaction covers its commands.
- Test scenarios: documentation examples compile where they use only Jido Chat APIs; public API and boundary contracts remain valid.
- Verification: Run full tests, contracts, and quality.
- Completion signal: Documentation names no required Ecto or Ash dependency and every repository gate passes.

### Work Graph

- Initial frontier: U1.
- After U1: U2 and U3 can proceed independently.
- Critical path: U1 -> U2 -> U4.
- Final integration unit: U4 after U2 and U3.

### Verification Contract

| Gate | Applies to | Evidence | Done signal |
| --- | --- | --- | --- |
| Storage behavior | U1 | `mix test test/jido_chat/runtime_storage_test.exs` | Memory and adapter validation pass |
| Durable restart | U2 | DETS storage tests | Records survive restart and failed Commit is absent |
| Bridge recovery | U3 | `mix test test/jido_chat/runtime_bridge_test.exs` | Lease recovery and no-resubmit rules pass |
| Public contracts | U4 | `mix test.contracts` | All obligations pass |
| Repository regression | U1-U4 | `mix test` | Full suite passes |
| Static quality | U1-U4 | `mix quality` | Formatter, compile, Credo, Dialyzer, and Doctor pass |

Run all commands from `/Users/mhostetler/Source/Jido/jido_chat/jido_chat`.

### Rollout and Recovery

The change is additive. Existing Memory users keep their configuration. A host enables DETS with a new path and table, or supplies its own adapter. There is no migration from old Messaging data. The DETS file can be backed up while the adapter is stopped. If an unsupported snapshot is found, startup fails and preserves the file for operator recovery.

### Risks and Assumptions

- Risk: A snapshot write succeeds but synchronization reports an uncertain result. The adapter returns a storage error and stops so it cannot continue with uncertain state.
- Risk: A short lease expires during a live provider call. Recovery does not reclaim a claim that is active in the current worker, and hosts can configure a larger lease.
- Risk: A custom adapter claims Commit without one real transaction. Adapter validation cannot prove database semantics; conformance tests and documentation make this an explicit adapter obligation.
- Risk: A DETS snapshot grows too large. DETS is the local reference, not the scale target; Ecto, Ash, or another indexed adapter is the production path.
- Assumption: Runtime domain values remain portable Erlang terms within the declared snapshot format version.

### Open Planning Decisions

None.

### Definition of Done

- R1-R8 have implementation and direct evidence.
- Memory behavior and current Runtime callers remain compatible.
- DETS retains all five capability record types across restart.
- Expired claims recover without resubmitting submitted or terminal work.
- Ecto and Ash integration require no dependency or special branch in Jido Chat.
- Focused tests, full tests, contracts, and quality pass.
- No commit, push, migration, package publication, or sibling-repository change occurs.

### Planning Sources

- Repository files listed under Product Contract Sources.
- `AGENTS.md`, `README.md`, `mix.exs`, `guides/architecture.md`, and `guides/runtime.md`.
- Official Ecto and Ash transaction documentation listed above.

## Adapter Results

- Markdown: canonical at `docs/plans/2026-11-16-0757-durable-chat-storage-plan.md`
- HTML: not requested
- Beadwork: not requested
