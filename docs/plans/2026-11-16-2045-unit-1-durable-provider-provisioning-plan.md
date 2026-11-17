---
title: Durable provider declarations and bridge provisioning
type: implementation-plan
date: 2026-11-16
last_reviewed: 2026-11-16
artifact_contract: kata-plan/v1
artifact_readiness: complete
domain: software
execution: code
product_contract_source: direct-request
---

# Durable Provider Declarations and Bridge Provisioning

## Goal Capsule

- Objective: A Jido Chat host can store provider account declarations and bridge bindings, activate them through its Jido instance, and recover them after a runtime or storage restart.
- Means: Add credential-free records, storage capabilities, a trusted definition registry, a host secret-resolver contract, runtime provisioning APIs, and managed reconciliation.
- Authority: Local changes and checks in Jido Chat. No commit, push, release, provider call, or remote retirement.
- Stop conditions: Stop before a destructive data change, a live provider call, a secret-store implementation, or a product-contract expansion.
- Next executor: Elixir package engineer.

## Product Contract

### Summary

Add the durable provider part of the Jido Chat V3 runtime without adding a secret store, a routing-policy system, or a storage-framework dependency.

### Problem Frame

The managed runtime can start provider account Agents from startup options. It cannot store those declarations, store dynamic bridge bindings, resolve host secrets at activation, or recover the same provider topology from durable storage. Bridge mappings are compiled into the Agent definition and allow only one outbound mapping for a local Room.

### Actors

- A host defines trusted provider account Agent modules.
- An operator provisions an account with opaque secret references and safe settings.
- A host secret resolver returns operation-scoped credentials at activation.
- The managed runtime reconciles the stored desired state through the host Jido instance.
- A bridge sends one local Room message to every enabled outbound binding in stable order.

### Requirements

- **R1:** A Runtime has a static `connection_definitions` registry from bounded string keys to trusted Agent modules. Stored data does not name modules or create atoms.
- **R2:** A durable connection declaration stores account ID, definition key, desired state, opaque secret references, safe settings, metadata, revision, and UTC times. It does not store resolved credentials.
- **R3:** A durable bridge binding stores account ID, local Room ID, external Room ID, direction, enabled state, metadata, revision, and UTC times.
- **R4:** Storage adapters can implement independent `Connections` and `Bindings` capabilities. The existing atomic `Commit` capability accepts their write commands.
- **R5:** The memory and DETS adapters implement the new capabilities. DETS reads older snapshots and writes the new format.
- **R6:** Provisioning persists desired state before reconciliation. Deprovisioning persists `:stopped`, stops the matching Agent, and keeps declarations, Room history, links, and provider work.
- **R7:** A configured host resolver maps opaque references to a credentials map only when an Agent must start. Jido Chat does not store, return, or log the resolved map.
- **R8:** Stored provider settings can replace only configuration keys that already exist in the trusted Agent definition. Unknown setting keys fail without atom creation.
- **R9:** Enabled bindings replace compiled Bridge mappings for a durable account. One account and external Room pair is unique. One local Room can have many outbound bindings, which run in deterministic external-Room order.
- **R10:** Static startup connection declarations and direct connection APIs continue to work.
- **R11:** A failed durable declaration does not stop another declaration or a Room from reconciling.
- **R12:** Focused tests, full package gates, and an Elixir design review prove the unit before Unit 2 starts.

### Public Flow

```text
trusted definition key + portable declaration
  -> durable connection record
  -> runtime reconcile
  -> trusted module lookup
  -> active binding lookup
  -> host secret resolution
  -> ephemeral Agent materialization
  -> host Jido activation
```

```text
local Room Signal
  -> active outbound bindings sorted by external Room ID
  -> one durable provider-work item per binding
  -> provider Agent commands
```

### Acceptance Examples

- A stored key `telegram-primary` resolves only through the host registry. A value such as `Elixir.Some.Module` is only a string and cannot load a module.
- A declaration with a secret reference contains no token before or after a DETS restart.
- A declaration with secret references and no resolver has an activation error while another declaration starts.
- A resolver exception produces a safe activation error and does not expose its return value or exception data.
- A stored setting can replace a trusted `poll_interval` key. A new `module` or `token` setting key is rejected.
- Two enabled outbound bindings for one local Room create two provider work items in stable order.
- A second binding for the same account and external Room conflicts.
- A declaration revision or binding revision change restarts the matching account Agent with the new runtime configuration.
- A stopped declaration remains stored and stays stopped after runtime restart.
- An older DETS snapshot restores with empty connection and binding maps, then writes format version 5.

### Scope Boundaries

Included: records, memory and DETS storage, storage behaviours, trusted registry, secret-resolver behaviour, Agent materialization, provisioning and query APIs, manager reconciliation, dynamic Bridge mappings, deterministic outbound broadcast, tests, and documentation.

Excluded: secret storage, token refresh, provider login, general routing policy, delivery fan-in policy, cross-account transactions, provider adapter migration, live provider calls, Assembly changes, reactions, Runtime Bus, remote release work, and compatibility with `jido_messaging`.

### Key Decisions

- Connection declaration identity is `account_id`.
- Binding identity is `{account_id, external_room_id}`. This enforces one inbound target for each provider Room.
- Durable records are retained. Deprovisioning changes desired or enabled state; it does not delete evidence.
- `secret_resolver` is an optional host module with `resolve/2`. It is required only when a starting declaration has nonempty secret references.
- The resolver receives the opaque reference map and a portable context with account ID, definition key, settings, and metadata. It returns only a credentials map.
- Durable settings overlay the trusted Chat client configuration by matching stored string keys to existing atom keys. The runtime never converts an untrusted string to an atom.
- Active binding external Room IDs become the Chat connection Room list. Active bindings become the Bridge mapping list.
- Dynamic mapping names are stable strings derived from the binding identity. Existing DSL mapping names can remain atoms.
- A durable configuration marker contains revisions, not secrets. The manager uses it to detect stale live Agents after its own restart.

### Rejected Alternatives

- Store modules in declarations: rejected because durable data would control code selection.
- Store resolved credentials: rejected because Jido Chat is not a secret store.
- Accept an anonymous resolver function: rejected because a named module is easier to supervise, document, and verify, and does not store a closure in Runtime configuration.
- Convert stored setting keys with `String.to_atom/1`: rejected because input could grow the atom table.
- Delete declarations during deprovision: rejected because restart behavior and audit evidence would become ambiguous.
- Copy the Jido Messaging routing-policy system: rejected because the selected V3 consumer needs explicit direction and broadcast only.

### Outstanding Questions

None. The owner approved all current recommendations on 2026-11-16.

## Planning Contract

### Current System

- `Jido.Chat.Runtime` has trusted Room definitions but no provider definition registry or secret resolver.
- `Jido.Chat.Runtime.Manager` merges startup and durable Room declarations. Provider declarations are startup-only.
- `Jido.Chat.Runtime.Connection` starts one Agent definition and injects Bridge runtime fields. It does not inject durable credentials, settings, or mappings.
- `Jido.Chat.Runtime.Bridge` uses compiled mappings. Mapping names must be atoms, and outbound mappings must be unique by local Room.
- Storage has Links, Outbox, Rooms, RoomDeclarations, Memberships, History, and Commit capabilities.
- Memory uses one `Storage.Engine`. DETS stores a history-free snapshot plus separate history records at format version 4.

### Target System

- Runtime configuration owns trusted connection definitions and an optional resolver module.
- Connection and Binding records are portable, revisioned, and credential-free.
- The storage engine and both built-in adapters support their complete lifecycle.
- The manager refreshes durable Room and connection declarations on every reconcile. It isolates entry failures and restarts only a connection whose durable configuration marker changed.
- Connection materialization resolves secrets only for a start, overlays safe settings, derives active Chat rooms, and installs active Bridge mappings.
- Public provisioning APIs persist first and reconcile second.

### Implementation Units

#### U1: Add records and storage capabilities

- Add `Runtime.Connection.Declaration` and `Runtime.Bridge.Binding` with constructors, updates, portable maps, fixed enums, revisions, and timestamps.
- Add `Storage.Connections` and `Storage.Bindings` behaviours.
- Extend `Storage.Adapter`, `Storage.Commit`, `Storage.Engine`, Memory, and DETS.
- Raise DETS format to 5 and restore missing maps as empty for older snapshots.
- Test constructors, portable round trips, conflicts, deterministic queries, commits, and restart.

#### U2: Add trusted materialization

- Add Runtime options and lookup functions for `connection_definitions` and `secret_resolver`.
- Add `Runtime.SecretResolver` behaviour and safe invocation.
- Split connection preparation from activation so secret resolution occurs once per start.
- Overlay credentials, trusted setting keys, dynamic Room IDs, dynamic Bridge mappings, and a revision-only configuration marker.
- Permit an empty compiled Bridge mapping set and string dynamic mapping names.
- Permit a trusted Chat connection to start with an empty Room list before durable bindings are applied.
- Test missing, failing, and successful resolution; unknown settings; absent Bridge plugin; and no secret disclosure.

#### U3: Add durable APIs and manager reconciliation

- Add durable query, create, update, desired-state, and binding-state helpers.
- Add Runtime facade functions for connection provisioning, connection updates, deprovisioning, and binding lifecycle.
- Merge startup and durable connection declarations with duplicate detection.
- Refresh declarations and bindings on reconcile, preserve live state when configuration is unchanged, and replace stale live Agents when revisions change.
- Keep a stopped declaration durable across manager and storage restart.
- Test unknown definitions, duplicate declarations, missing capabilities, isolated failures, restart adoption, revision restart, deprovision, and static compatibility.

#### U4: Verify and simplify

- Update Runtime and Bridge documentation.
- Run focused storage, manager, connection, and bridge tests.
- Run formatting, warnings-as-errors compilation, the full suite, contracts, quality, docs, coverage, and unused-dependency checks.
- Run the Elixir design review, fix all supported findings, and repeat affected gates.

### Work Graph

- Initial frontier: U1.
- Critical path: U1 -> U2 -> U3 -> U4.
- Final integration unit: U4.
- Next goal unit after completion: Unit 2, Assembly chat data and queries.

### Verification Contract

Run from `/Users/mhostetler/Source/Jido/jido_chat/jido_chat`.

| Gate | Evidence | Done signal |
| --- | --- | --- |
| Record boundary | focused record tests | fixed fields, portable maps, no arbitrary atom or credential storage |
| Storage capability | memory and DETS tests | create, update, conflict, query, commit, restart, and version migration pass |
| Secret boundary | connection tests | missing and failed resolution are safe; credentials exist only in the active Agent |
| Managed recovery | manager tests | activation, stop, restart, revision replacement, isolation, and durable recovery pass |
| Bridge routing | bridge tests | duplicate external binding fails and local outbound broadcast is deterministic |
| Package contracts | full tests and Covenant | no public contract regression |
| Repository quality | quality, docs, coverage, unused dependencies | all configured gates pass |
| Design review | `kata-ex-design-review` | no accepted finding remains |

Supported commands:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test test/jido_chat/runtime_storage_test.exs test/jido_chat/runtime_storage_dets_test.exs
mix test test/jido_chat/runtime_manager_test.exs test/jido_chat/runtime_bridge_test.exs
mix test
mix test.contracts
mix quality
mix docs
mix coveralls
mix deps.unlock --check-unused
git diff --check
```

### Rollout and Recovery

This unit changes only local source and tests. Built-in storage restores old snapshots by adding empty connection and binding maps. It never deletes Room history. If a new record or manager path fails, keep the prior static connection path active and correct the scoped unit. Do not add a compatibility adapter or weaken record validation.

### Risks and Assumptions

- Risk: dynamic plugin data can bypass compile-time DSL verification. Mitigation: rerun Bridge normalization and route verification after every overlay.
- Risk: a manager restart can adopt an Agent that uses an old binding set. Mitigation: store a revision-only configuration marker in the active Agent snapshot and compare it before adoption.
- Risk: resolver errors can expose secret values. Mitigation: collapse resolver failures to stable public atoms and never include returned data in status.
- Risk: settings can become a code-selection channel. Mitigation: permit only keys that exist in the trusted client configuration and never create atoms.
- Risk: broadcast can create duplicate work. Mitigation: stable binding identity and existing outbox idempotency rules apply to each mapping.
- Assumption: each trusted provider definition has exactly one Chat connection, as required by the current Runtime contract.
- Assumption: an account that uses durable bindings includes the Bridge plugin and the required routes in trusted code.

### Definition of Done

- R1 through R12 have tests or named gate evidence.
- Memory and DETS implement Connections, Bindings, and the extended Commit capability.
- No durable value contains a resolved credential or module selected by stored input.
- Durable accounts recover in the requested state after runtime and storage restart.
- One failed account does not block another account or Room.
- Static declarations and direct connection calls still pass.
- The package gates pass.
- The design review has no accepted open finding.

### Planning Sources

- [Approved goal brief](./2026-11-16-1135-jido-chat-assembly-v3-goal-brief.md)
- [Unit 0 plan](./2026-11-16-1714-unit-0-consolidated-jido-v3-baseline-plan.md)
- `lib/jido_chat/runtime.ex`
- `lib/jido_chat/runtime/manager.ex`
- `lib/jido_chat/runtime/connection.ex`
- `lib/jido_chat/runtime/bridge.ex`
- `lib/jido_chat/runtime/storage/**`

## Adapter Results

- Markdown: canonical at `docs/plans/2026-11-16-2045-unit-1-durable-provider-provisioning-plan.md`
- HTML: not requested
- Beadwork: not requested

## Execution Results

- Status: complete on 2026-11-16.
- Repository start and end commit: `810ef0c265dae238d5971dc8f4ed65bab1f93892`.
  The unit remains in the local working tree. No checkpoint commit was authorized.
- Added portable connection declarations and bridge bindings with revisions,
  UTC times, desired or enabled state, and opaque secret references.
- Added independent Connections and Bindings storage capabilities to Memory,
  DETS, Commit, and the storage engine. DETS now writes format version 5 and
  restores versions 1 through 5.
- Added trusted provider definition lookup, host secret resolution, safe
  setting overlays, dynamic Chat Rooms, and dynamic Bridge mappings.
- Added durable provisioning, query, update, deprovision, manager recovery,
  and one-to-many local message link APIs.
- Kept startup declarations and direct connection APIs active.

## Design Review Results

The Elixir design review found four supported issues. All four are fixed:

- Durable accounts can now run with a Connections-only adapter when they do
  not use durable bindings.
- Snapshot restore now rejects damaged or inconsistent local and external link
  indexes without raising.
- Binding deprovision now returns the stored binding and activation evidence.
- Shared manager refresh logic and binding page collection are simpler, and a
  stalled adapter page fails instead of looping.

No accepted finding remains.

## Verification Results

- Focused provider record, storage, DETS, manager, and bridge tests: 60 passed.
- Full package tests: 455 passed.
- Covenant: 28 tests passed and 25 of 25 obligations covered.
- Coverage: 90.1%, above the configured 90% threshold.
- `mix quality`: passed with no Credo or Dialyzer issue; Doctor passed.
- `mix docs`: completed. Existing hidden upstream callback reference warnings
  remain unchanged.
- Unused dependency check: passed.
- Compile dependency graph: 168 files, 180 compile edges, zero cycles.
- `git diff --check`: passed.
