---
title: Add the managed Jido Chat Runtime process tree
type: implementation-plan
date: 2026-11-16
last_reviewed: 2026-11-16
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Add the managed Jido Chat Runtime process tree

## Goal Capsule

- Objective: Let a host start one optional Chat Runtime supervisor that keeps declared Room Agents and provider account Agents in the required running or stopped state.
- Means: Add a small Runtime supervisor and manager. The manager uses the public Jido Agent APIs. Jido continues to own all Agent processes.
- Authority: Local writes in `jido_chat`. Do not commit, push, publish, or release.
- Stop conditions: Stop if the design needs a second Agent supervisor, a new package, a stored-data change, or a change to Jido.
- Next executor: Elixir package implementer and verifier.

## Product Contract

### Summary

A host can add its `Jido.Chat.Runtime` facade to its supervision tree. The facade manages declared local rooms and provider accounts through the host-owned Jido instance.

### Problem Frame

The current Runtime has process-free helpers. A host must start each Room and provider account itself. There is no one place to start, inspect, stop, restart, or reconcile a group of Chat Agent activations.

### Actors

- The host application owns the application supervision tree, one Jido instance, storage resources, and Runtime configuration.
- The Runtime manager owns the desired state of the declared Chat Agent activations.
- Jido owns Agent activation, supervision, restart, and shutdown.

### Requirements

- **R1:** A host can start the Runtime facade as an optional supervised child. Starting the `:jido_chat` application must still start no Runtime process.
- **R2:** Runtime configuration can declare Room Agents and provider account Agents that must run after initial reconciliation.
- **R3:** The host can list status and can start, stop, restart, or reconcile each declared room and provider account.
- **R4:** Reconciliation is safe to repeat. It adopts a matching live Agent, starts a missing required Agent, stops a live Agent whose desired state is stopped, and rejects an address that belongs to a different Agent definition.
- **R5:** One failed declaration must not stop other valid declarations. The manager must retry failed or missing required Agents.
- **R6:** Jido remains the only Agent process owner. The Runtime tree must not add a RoomServer, Agent supervisor, Registry, or provider-specific process owner.
- **R7:** Existing process-free Runtime and direct provider connection APIs remain compatible when the managed tree is not used.

### Key Flows

```text
host supervisor
  -> host Jido instance
  -> optional Chat Runtime supervisor
       -> Runtime manager
            -> validate declaration
            -> resolve stable Jido Agent Address
            -> adopt, start, or stop through Jido
            -> record local status
```

Rooms are reconciled before provider accounts. This order makes local Room addresses available before a Bridge account starts.

### Acceptance Examples

1. A host starts `{MyApp.Chat, rooms: [{"support", MyApp.SupportRoom}]}` after `MyApp.Jido`. The room is ready at the stable `"support"` Agent Address.
2. A host declares one room and one provider account. `runtime_status/0` reports both as running after initial reconciliation.
3. The host stops a declared room. Repeated background reconciliation keeps it stopped. The host starts it again, and the same stable Address becomes ready.
4. A declared Agent is stopped outside the manager. The next reconciliation starts it again.
5. One invalid provider account reports an error. A valid room in the same Runtime still starts.
6. A live Agent with a different definition uses a declared Address. Runtime reports an address conflict and does not stop or replace that Agent.
7. A host that does not start `MyApp.Chat` can still call the existing `start_connection/2`, `stop_connection/1`, and status functions.

### Success Criteria

- The public managed lifecycle works through a Runtime facade.
- Focused lifecycle and recovery tests pass.
- The full package test and quality gates pass.
- The architecture and Runtime guides state the correct process ownership.

### Scope Boundaries

In scope:

- Optional Runtime supervisor startup.
- Declarative in-memory desired state for rooms and provider accounts.
- Initial and periodic reconciliation.
- Local lifecycle and status APIs.
- Normal Runtime shutdown cleanup.

Out of scope:

- A durable room or account catalog.
- Dynamic creation of declarations after Runtime startup.
- Automatic room membership or Bridge mapping creation.
- A second Agent supervisor or a replacement for Jido activation.
- Cluster-wide coordination.
- New dependencies.

### Key Decisions

- Runtime declarations are startup configuration. A Runtime restart restores that configuration and sets each declaration to its initial running state.
- A manual stop changes desired state only for the current Runtime manager lifetime.
- Runtime shutdown stops managed Agent activations. An unexpected manager failure leaves Agent activations in Jido, and the restarted manager adopts them.
- Runtime errors are local status. They are not stored Signals or durable Chat records.

### Rejected Alternatives

- Copy the old `jido_messaging` RoomServer, AgentSupervisor, Registries, and ConfigStore: rejected because these processes duplicate Jido V3 ownership.
- Put managed children directly under the Runtime supervisor: rejected because Jido must own Agent activation and Plugin process lifetime.
- Add a durable catalog now: rejected because catalog persistence is a separate storage capability and is not required for this process-tree slice.

### Dependencies

- The consolidated Jido V3 public Address, activation, resolution, snapshot, readiness, and stop APIs.
- Existing `Jido.Chat.Runtime.Room`, `Jido.Chat.Runtime.Connection`, and Chat Plugin contracts.

### Outstanding Questions

None. Durable declarations are a stated later feature.

### Sources

- Direct user request on 2026-11-16.
- `lib/jido_chat/runtime.ex`
- `lib/jido_chat/runtime/room.ex`
- `lib/jido_chat/runtime/connection.ex`
- `guides/architecture.md`
- `guides/runtime.md`
- Consolidated Jido dependency source under `deps/jido/lib/jido.ex` and `deps/jido/lib/jido/agent_server.ex`.

## Planning Contract

### Product Contract Preservation

Product Contract unchanged.

### Current System

`Jido.Chat.Runtime` creates a module facade with configuration and direct provider account helpers. It has no `child_spec/1` or `start_link/1`. `Jido.Chat.Runtime.Room.start_agent/3` and `Jido.Chat.Runtime.Connection.start/3` start Agents through the host Jido instance. The architecture guide shows Room, participant, and provider account Agents only below Jido.

### Target System

The Runtime facade gains an optional supervisor child specification. `Jido.Chat.Runtime.Supervisor` owns one internal manager process. The manager stores the configured desired state and calls the existing Jido and Chat lifecycle boundaries. It never links an Agent as its child.

The lifecycle states are:

```text
pending -> running
pending -> error -> running
running -> stopped -> running
running -> error -> running
```

`desired: :running | :stopped` controls reconciliation. `state: :pending | :running | :stopped | :error` reports the observed result. A repeated operation must produce the same required process state.

### Key Technical Decisions

#### KTD1: Use one optional Runtime supervisor and one manager

- **Decision:** Generate `child_spec/1` and `start_link/1` in each Runtime facade. Start one `Jido.Chat.Runtime.Manager` below `Jido.Chat.Runtime.Supervisor`.
- **Reason:** R1 and R6 need a host-owned process-tree entry without duplicate Agent ownership.
- **Rejected alternative:** Add each Agent as a Runtime supervisor child. This would bypass the Jido activation contract.
- **Consequences:** The host must start Jido before the Runtime facade. Runtime can stay alive and report errors if Jido is temporarily unavailable.
- **Governs:** R1, R6, U1, U2.

#### KTD2: Use declarative startup configuration as the catalog

- **Decision:** Accept unique `{id, definition}` pairs in `:rooms` and `:connections`. Store desired state only in the manager.
- **Reason:** This is the smallest complete managed-tree slice and does not add a new storage contract.
- **Rejected alternative:** Add a mutable or durable ConfigStore. This would pull the next catalog feature into this unit.
- **Consequences:** Manual stop state does not survive a manager restart. Static declarations do survive because the supervisor starts the manager with the original options.
- **Governs:** R2, R3, R7, U1, U2, U3.

#### KTD3: Reconcile through stable Jido Addresses

- **Decision:** Resolve each Agent by its complete Address. Adopt it only when its definition identity matches. Start or stop it only through public Jido APIs.
- **Reason:** R4 and R6 require repeatable lifecycle work with one process owner.
- **Rejected alternative:** Register separate Runtime process names. This would create a second identity and ownership system.
- **Consequences:** A conflicting Agent is not replaced. Module-backed Agent definitions give the strongest identity check. Map definitions also use stable definition fields and Plugin providers.
- **Governs:** R4, R6, U2.

#### KTD4: Isolate failures and retry with bounded work

- **Decision:** Reconcile rooms before connections, continue after one entry fails, and schedule one later reconcile timer. Each pass handles declarations in sorted ID order.
- **Reason:** R5 requires partial progress and recovery. The configured declaration count bounds one pass.
- **Rejected alternative:** Fail the Runtime supervisor when one Agent cannot start. This would stop valid rooms and remove status access.
- **Consequences:** Runtime can be ready but unhealthy. `runtime_status/0` shows entry errors. `reconcile_runtime/0` returns a partial-failure result when errors remain.
- **Governs:** R3, R5, U2, U3.

#### KTD5: Preserve direct APIs and make managed APIs additive

- **Decision:** Keep `start_connection/2`, `stop_connection/1`, `connection_status/1`, and bridge functions unchanged. Add separate managed lifecycle functions.
- **Reason:** R7 requires current callers to keep the same behavior.
- **Rejected alternative:** Route existing direct functions through the manager when it is present. This would give one function two different contracts.
- **Consequences:** A host must use the managed stop and start functions for declared entries. The guide will make this difference explicit.
- **Governs:** R3, R7, U1, U3.

### System Boundaries and Change Surface

| Surface | Current contract | Planned change | Compatibility or risk |
| --- | --- | --- | --- |
| `Jido.Chat.Runtime` facade | Process-free configuration and direct helpers | Add optional child startup plus managed status and lifecycle delegates | Additive public API |
| `Jido.Chat.Runtime.Supervisor` | Does not exist | Public supervisor boundary and facade for manager calls | Starts only when the host selects it |
| `Jido.Chat.Runtime.Manager` | Does not exist | Internal desired-state and reconciliation process | Must not own Agent children |
| Room activation | Host calls `Room.start_agent/3` | Manager calls the same boundary and waits for readiness | Stable Address and Room Plugin required |
| Provider account activation | Host calls `Connection.start/3` | Manager calls the same boundary and can adopt a matching live account | Existing direct API stays unchanged |
| Shutdown | Host stops each Agent | Normal Runtime shutdown stops its declared Agent activations before Jido stops | Unexpected manager failure leaves Agents for adoption |
| Guides and architecture | Manual-only Runtime tree | Show optional managed tree and ownership | Must not imply automatic application startup |

Public managed API shapes:

- `runtime_status/0 :: {:ok, map()} | {:error, :runtime_not_started}`
- `reconcile_runtime/0 :: {:ok, map()} | {:error, term()}`
- `list_managed_rooms/0` and `list_managed_connections/0` return entry status
  lists.
- `room_runtime_status/1` and `managed_connection_status/1` return one entry status.
- `start_managed_room/1`, `stop_managed_room/1`, and `restart_managed_room/1` change one declared room.
- `start_managed_connection/1`, `stop_managed_connection/1`, and `restart_managed_connection/1` change one declared account.

An entry status includes `id`, `definition`, `desired`, `state`, `ref`, `pid`, and `error`. It does not include credentials or Agent state.

### Implementation Units

#### U1: Add the optional managed Runtime boundary

- **Outcome:** A Runtime facade can start as a supervised child with validated room, connection, and reconcile options.
- **Requirements:** R1, R2, R7.
- **Dependencies:** None.
- **Affected surfaces:** `lib/jido_chat/runtime.ex` for generated functions and Boundary export; new `lib/jido_chat/runtime/supervisor.ex` for host startup and managed API dispatch.
- **Implementation direction:** Keep startup optional. Use fixed process names derived from the Runtime facade module. Accept only `:rooms`, `:connections`, and `:reconcile_interval`. Reject duplicate or malformed declaration IDs before the manager enters its loop.
- **Test scenarios:** Empty Runtime startup; declared option validation; no Runtime process after normal `:jido_chat` application startup; existing direct functions without a manager.
- **Verification:** Focused managed Runtime tests and compilation with warnings as errors.
- **Completion signal:** The facade starts and stops one Runtime supervisor without starting an Agent supervisor.

#### U2: Implement ordered Agent reconciliation and lifecycle

- **Outcome:** The manager starts, adopts, stops, restarts, and recovers declared Room and provider account Agents through Jido.
- **Requirements:** R2, R3, R4, R5, R6.
- **Dependencies:** U1.
- **Affected surfaces:** New `lib/jido_chat/runtime/manager.ex`; existing Room and Connection public functions as lifecycle boundaries; new focused test fixture and tests.
- **Implementation direction:** Reconcile rooms before connections. Validate required Plugins. Compare live snapshots before adoption or stop. Wait for Agent readiness after start. Continue after an entry error. Use one timer for later retry. On normal shutdown, stop matching declared Agents. Do not stop a conflicting Agent.
- **Test scenarios:** Initial room and connection startup; matching adoption; stop, start, and restart; external stop recovery; missing Jido recovery; invalid definition isolation; conflicting address protection; normal shutdown cleanup; unexpected manager restart adoption.
- **Verification:** Run the focused managed Runtime test file. Inspect the Jido child list to confirm Agent workers stay below Jido, not below Runtime.
- **Completion signal:** All lifecycle states and recovery examples pass at the public Runtime facade.

#### U3: Document the managed tree and complete package integration

- **Outcome:** Host setup, ownership, limits, and managed versus direct API use are clear, and all package gates pass.
- **Requirements:** R1 through R7.
- **Dependencies:** U2.
- **Affected surfaces:** `guides/runtime.md`, `guides/architecture.md`, `guides/source_layout.md`, public API tests or docs when required by the repository gates.
- **Implementation direction:** Show Jido before Runtime in the host child list. State that the application still starts no Chat process. State that declarations and manual desired state are in memory. Update the process tree to show the manager beside the host Jido instance and Agents below Jido.
- **Test scenarios:** Documentation examples match the public function names and configuration shape; the existing bridge and room suites still pass.
- **Verification:** Full tests, contract tests, quality, documentation warnings, diff checks, and independent design verification.
- **Completion signal:** Required gates pass and no guide assigns Agent ownership to Runtime.

### Work Graph

- Initial frontier: U1.
- Critical path: U1 -> U2 -> U3.
- Parallel work: None. Each unit changes the contract used by the next unit.
- Final integration unit: U3.

### Verification Contract

| Gate | Applies to | Evidence | Done signal |
| --- | --- | --- | --- |
| Focused lifecycle | U1, U2 | New managed Runtime ExUnit tests | All acceptance and recovery cases pass |
| Runtime regression | U2, U3 | Existing Room, Bridge, and storage tests | Existing direct behavior passes |
| Contract | U3 | Covenant and contract test commands | All active contracts pass |
| Repository | U3 | Full tests and `mix quality` | No package regression or static failure |
| Documentation | U3 | `mix docs` and source review | Examples match the API and changed modules add no warning |
| Architecture review | U3 | Read-only review of the final diff and process ownership | No second Agent owner or avoidable process remains |

Run from `/Users/mhostetler/Source/Jido/jido_chat/jido_chat`:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test test/jido_chat/runtime_manager_test.exs
mix test test/jido_chat/runtime_room_test.exs test/jido_chat/runtime_bridge_test.exs test/jido_chat/runtime_storage_test.exs
mix test test/contracts
mix test.contracts
mix test
mix quality
mix docs -f html -f markdown
git diff --check
git status --short
```

Requirement traceability:

| Requirement | Units | Verification |
| --- | --- | --- |
| R1 | U1, U3 | Empty startup and application-startup test; documentation review |
| R2 | U1, U2 | Initial reconciliation integration test |
| R3 | U2, U3 | Public list, status, start, stop, restart, and reconcile tests |
| R4 | U2 | Adoption, repeat, external stop, and address conflict tests |
| R5 | U2 | Partial failure and retry tests |
| R6 | U2, U3 | Supervisor ownership assertion and architecture review |
| R7 | U1, U3 | Existing direct Runtime regression suite |

### Rollout and Recovery

This is an opt-in additive feature. A host enables it only when it adds its Runtime facade to its child list. Removing that child returns the host to direct lifecycle control. No stored data or schema changes occur. During a normal shutdown, the Runtime stops its declared Agent activations. If a manager fails unexpectedly, its supervisor restarts it and it adopts matching Agents that remain under Jido.

### Risks and Assumptions

- Risk: A short reconcile interval can cause avoidable work. Mitigation: one timer and a documented positive interval with a practical default.
- Risk: Runtime could stop an unrelated Agent at the same Address. Mitigation: verify definition identity before adoption or stop, and test the conflict case.
- Risk: One provider failure can block Room setup. Mitigation: ordered, per-entry reconciliation with independent status.
- Risk: A host can use direct stop on a managed account, after which reconciliation starts it again. Mitigation: separate managed function names and clear guide text.
- Assumption: The host starts the named Jido instance before the Runtime child. The manager still retries if Jido later restarts.

### Open Planning Decisions

None. A durable catalog and dynamic declaration API are deferred product features.

### Definition of Done

- The optional Runtime supervisor and manager implement R1 through R7.
- Jido is the only owner of Room and provider account Agent processes.
- The public managed lifecycle and status tests pass.
- Existing direct Runtime behavior passes without a manager.
- The full test, contract, quality, documentation, and diff gates pass.
- Runtime and architecture guides show the new tree and its in-memory limits.
- No new dependency, stored-data shape, commit, push, publish, or release occurs.

### Planning Sources

- Repository source and tests at local HEAD `cfce0256b468bcf14819a18a9ded7c58765213f9`.
- Consolidated Jido dependency at `047bf746330a2fbe7c3b25c045552e0303c97eaf`.
- Jido kata plan, work, and verification methods selected by the user.

## Adapter Results

- Markdown: canonical at `docs/plans/2026-11-16-0939-managed-runtime-process-tree-plan.md`
- HTML: not requested
- Beadwork: not requested
