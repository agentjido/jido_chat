---
title: Runtime realtime and host presence boundary
type: implementation-plan
date: 2026-11-16
last_reviewed: 2026-11-16
artifact_contract: kata-plan/v1
artifact_readiness: complete
domain: software
execution: code
product_contract_source: direct-request
---

# Runtime Realtime and Host Presence Boundary

## Goal Capsule

- Objective: A host can observe committed facts from every managed durable Room
  through one Runtime Bus and can connect its own presence system without a
  Phoenix dependency in Jido Chat.
- Means: Add one supervised Jido Signal Bus before the Runtime manager, a small
  Runtime Bus boundary, facade subscribe and unsubscribe functions, Room fact
  fan-out, tests, and documentation.
- Authority: Local Jido Chat changes and checks. No commit, push, live provider
  call, Assembly change, Phoenix dependency, or remote retirement.
- Stop conditions: Stop before a second event protocol, a presence table,
  heartbeat or TTL state, a new persistence package, or a compatibility API.
- Next executor: Elixir package engineer.

## Product Contract

### Requirements

- **R1:** Starting the optional managed Runtime starts one bounded
  `Jido.Signal.Bus` before the Runtime manager. Starting `:jido_chat` still
  starts no process.
- **R2:** The Runtime facade returns the Bus and supplies subscribe and
  unsubscribe functions that keep native Jido paths, selectors, targets, and
  subscription IDs.
- **R3:** After storage accepts a durable message or reaction change, its Room
  publishes the same Signal to the Room Bus and the Runtime Bus. No wrapper
  event or second PubSub contract is added.
- **R4:** A missing or restarting Runtime Bus does not undo durable storage or
  fail a committed Room turn. Storage is authoritative; notification is a cue
  to read it again.
- **R5:** Rejected Room commands publish no Runtime fact. Repeated reaction
  commands publish no duplicate fact.
- **R6:** Ordinary subscriber exit cleanup and Runtime restart behavior use
  Jido Bus ownership. A host reattaches after a Runtime restart.
- **R7:** Jido Chat stores no presence session. Phoenix Presence, heartbeat,
  TTL, and UI transport remain in Assembly or another host.
- **R8:** Focused tests, full package gates, and an Elixir design review pass
  before provider adapter migration starts.

### Public Flow

```text
durable Room command
  -> storage commit
  -> Room Bus publish
  -> best-effort Runtime Bus publish
  -> host subscriber
  -> host rereads durable projection
```

### Key Decisions

- The Runtime Bus is a native `Jido.Signal.Bus` with a fixed bounded in-memory
  log. This unit does not add a Bus store adapter.
- The Bus name is stable for one Runtime module and isolated by the Runtime's
  host Jido instance.
- `runtime_bus/0` exposes the native Bus PID for advanced Jido Bus operations.
  `subscribe_runtime/2` and `unsubscribe_runtime/2` cover the normal host path.
- The Room Bus remains the Room and Agent interaction boundary. The Runtime Bus
  is the application-wide observation boundary.
- A Runtime Bus error is best effort only. The existing Room Bus error contract
  is unchanged.
- The host receives `jido.chat.room.message` and canonical reaction facts. It
  uses each fact's Room identity to read the correct durable state.

### Scope Boundaries

Included: supervised Bus ownership, stable identity, native subscription
delegation, message and reaction fan-out, multi-Room tests, subscriber cleanup,
restart and failure tests, documentation, quality gates, and design review.

Excluded: Phoenix, Presence, PubSub, Hologram transport, persistent Bus stores,
global ordering across storage and Bus, replay facade wrappers, message edits,
receipts, provider adapter changes, Assembly source, and Jido Messaging
compatibility.

## Planning Contract

### Implementation Units

1. **U1 - Bus ownership and facade.** Add the Runtime Bus module, put its child
   before the manager, validate the bounded log option, and expose native lookup,
   subscribe, and unsubscribe functions.
2. **U2 - Committed fact fan-out.** Publish durable Room messages and changed
   reactions to the Runtime Bus after the existing Room Bus publication. Treat
   the Runtime notification as best effort.
3. **U3 - Lifecycle evidence.** Test multiple dynamic Rooms, rejected and
   duplicate commands, subscriber exit, Runtime restart and reattachment, and
   durable commit while the Runtime Bus is unavailable.
4. **U4 - Verify and simplify.** Update docs, run all gates, run the Elixir
   design review, fix supported findings, and repeat affected gates.

### Verification Contract

Run from `/Users/mhostetler/Source/Jido/jido_chat/jido_chat`.

- Supervisor tests prove the Bus and manager are the only Runtime-owned
  children and the Bus is available when manager reconciliation completes.
- Runtime Bus tests prove native path delivery, two Room identities,
  unsubscribe, target exit cleanup, and restart reattachment.
- Durable Room tests prove storage remains committed when the Runtime Bus is
  absent and rejected or idempotent commands produce no Runtime fact.
- Full tests, Covenant, quality, docs, 90% coverage, unused dependencies,
  compile-connected xref, and `git diff --check` pass.

### Risks and Mitigations

- Risk: Runtime notification failure changes the command result. Mitigation:
  Runtime publication is best effort after the required Room publication.
- Risk: a second event family diverges from Room facts. Mitigation: publish the
  exact Signal struct, without a wrapper.
- Risk: the observation log becomes an unbounded source of state. Mitigation:
  use the bounded Jido memory store and keep durable chat state in storage.
- Risk: core takes ownership of web presence. Mitigation: expose only native
  fact subscription and document the host presence boundary.

### Definition of Done

- R1 through R8 have test or gate evidence.
- The managed Runtime owns exactly one Runtime Bus and one manager.
- Two Rooms can notify one host subscriber through the Runtime Bus.
- A stopped Runtime Bus does not roll back a durable Room message.
- No Phoenix or presence dependency enters Jido Chat.
- No accepted design-review finding remains.

### Planning Sources

- [Approved goal brief](./2026-11-16-1135-jido-chat-assembly-v3-goal-brief.md)
- [Completed Unit 2 plan](./2026-11-16-1810-unit-2-durable-reactions-plan.md)
- `lib/jido_chat/runtime.ex`
- `lib/jido_chat/runtime/supervisor.ex`
- `lib/jido_chat/runtime/room/plugin.ex`
- Installed consolidated Jido `Jido.Signal.Bus`

## Adapter Results

- Markdown: canonical at `docs/plans/2026-11-16-1825-unit-3-runtime-realtime-boundary-plan.md`
- HTML: not requested
- Beadwork: not requested

## Execution Result

Completed in the local working tree on 2026-11-16.

- Added one bounded `Jido.Signal.Bus` before the Runtime manager and exposed
  native lookup, subscribe, and unsubscribe operations through the Runtime
  facade.
- Published the exact committed Room message and reaction Signals to the
  Runtime Bus after their required Room Bus publication.
- Kept Runtime notification best effort. A missing or restarting Runtime Bus
  does not undo an accepted storage commit.
- Proved multi-Room delivery, rejected and idempotent command silence,
  unsubscribe behavior, subscriber cleanup, Runtime restart and reattachment,
  and durable commit during a Bus failure.
- Kept presence, heartbeat, TTL, sessions, Phoenix, and UI transport outside
  Jido Chat.

## Design Review Result

The Elixir design review found and fixed two issues.

1. Runtime Bus lookup caught all exceptions. It now checks the Runtime module
   contract explicitly and reports the supported missing-Runtime result.
2. Room shutdown trusted an asynchronous Jido address transition. It now waits
   for stable address removal and handles the temporary recovery state. The
   race fix passed the focused suite in 11 consecutive seeded runs.

No accepted finding remains.

## Verification Result

- Focused Runtime, manager, and durable Room tests: 34 passed.
- Focused race repetition: 11 consecutive runs passed with 34 tests per run.
- Full suite through coverage: 473 passed; total coverage is 90.3%.
- Covenant: 28 tests passed; 25 of 25 obligations hold.
- `mix quality`: passed, including Credo, Dialyzer, and Doctor.
- Documentation: generated HTML and Markdown. The unchanged hidden upstream
  `Jido.Agent.Extension` callback-reference warnings remain.
- Unused dependencies: none.
- Compile graph: 171 files, 182 compile edges, zero cycles.
- `git diff --check`: passed.
