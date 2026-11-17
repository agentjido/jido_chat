---
title: Durable reactions and chat projection queries
type: implementation-plan
date: 2026-11-16
last_reviewed: 2026-11-16
artifact_contract: kata-plan/v1
artifact_readiness: complete
domain: software
execution: code
product_contract_source: direct-request
---

# Durable Reactions and Chat Projection Queries

## Goal Capsule

- Objective: Jido Chat stores authorized local reactions as durable current
  state and supplies bounded queries that Jido Assembly can project.
- Means: Add one reaction record, one independent storage capability, Room
  commands, canonical reaction facts, Runtime query functions, built-in adapter
  support, tests, and documentation.
- Authority: Local Jido Chat changes and checks. No commit, push, live provider
  call, Assembly change, or remote retirement.
- Stop conditions: Stop before mutable message history, a profile or search
  model in core, a Phoenix dependency, or a compatibility API.
- Next executor: Elixir package engineer.

## Product Contract

### Summary

Add the minimum durable reaction contract required by Assembly. Keep immutable
message history and derive threads from existing history fields and queries.

### Requirements

- **R1:** A portable reaction record has stable identity from Room, message,
  reaction value, and actor. It stores current active or removed state,
  revision, and UTC times.
- **R2:** Add and remove are idempotent. A real state change increases the
  revision. A repeated request returns committed evidence but publishes no new
  fact.
- **R3:** Only an active Room member can change that caller's reaction. The
  retained message must exist in the same Room.
- **R4:** A successful state change publishes the existing canonical
  `jido.chat.reaction.added` or `jido.chat.reaction.removed` Signal on the Room
  Bus only after storage accepts the change.
- **R5:** Storage adapters can implement an independent `Reactions` capability.
  `Commit` accepts reaction insert and update commands.
- **R6:** Reaction queries are bounded, deterministic, cursor-based, and can
  filter current state for one message or a bounded set of message IDs.
- **R7:** Memory and DETS implement reactions. DETS reads older snapshots with
  an empty reaction map and writes format version 6.
- **R8:** Runtime exposes get and list reaction queries. Message history remains
  immutable. Thread roots and replies continue to derive from `thread_id`,
  `reply_to_id`, and bounded history queries.
- **R9:** No user profile, search result, presence session, mutable message
  reaction field, or separate thread record enters Jido Chat core.
- **R10:** Focused tests, full package gates, and an Elixir design review pass
  before Unit 3 starts.

### Public Flow

```text
Room reaction command
  -> host identity resolution
  -> active-member authorization
  -> retained message check
  -> reaction insert or revision update
  -> canonical reaction fact
  -> Room Bus publication
  -> correlated committed reply
```

### Key Decisions

- Reaction identity is `{room_id, message_id, reaction, actor_key}`. The stable
  record ID is also the query cursor.
- Actor values use the same portable string or Agent Address shape as Room
  membership.
- Current state uses `:active` and `:removed`. Records are not deleted.
- A repeated add or remove is a committed no-op with `changed: false`.
- Queries default to active reactions and sort by message ID, reaction value,
  and actor key.
- One query accepts at most 100 message IDs and returns at most 1,000 records.
- Canonical provider reaction facts are reused. No second public reaction event
  family is added.
- Threads remain a history projection. This unit adds tests and documentation,
  not a durable Thread record.

### Scope Boundaries

Included: reaction record and transitions, storage behavior, Memory and DETS,
Commit commands, Room command Signals, authorization, message existence,
canonical facts, Room Bus publication, Runtime queries, restart and cursor
tests, documentation, quality gates, and design review.

Excluded: edits, deletes, receipts, reaction counts stored on messages, global
search, profiles, presence, Runtime-wide Bus, provider adapter reactions,
Assembly code, and Jido Messaging compatibility.

## Planning Contract

### Implementation Units

1. **U1 - Record and storage.** Add the record, capability, storage engine,
   adapters, Commit commands, DETS format 6, queries, and migration tests.
2. **U2 - Room command flow.** Add request and reply Signals, Room routes,
   Plugin preparation and authorization actions, durable transition logic,
   canonical facts, and post-storage publication.
3. **U3 - Runtime projection API.** Add get and list functions, bounded message
   filters, cursor behavior, and thread derivation evidence.
4. **U4 - Verify and simplify.** Update docs, run all gates, run the Elixir
   design review, fix all supported findings, and repeat affected gates.

### Verification Contract

Run from `/Users/mhostetler/Source/Jido/jido_chat/jido_chat`.

- Record tests prove portable actor identity, stable IDs, transitions, and
  invalid input rejection.
- Storage tests prove insert, update conflict, current-state filters, bounded
  message sets, cursors, Commit atomicity, restart, and migration.
- Room tests prove add, duplicate add, remove, repeated remove, missing message,
  wrong Room, nonmember, storage failure, publication order, and restart.
- Existing history tests prove thread filtering and immutable messages.
- Full tests, Covenant, quality, docs, 90% coverage, unused dependencies, xref,
  and `git diff --check` pass.

### Risks and Mitigations

- Risk: a fact is published before durable state. Mitigation: the Action creates
  a Publish directive only after the adapter returns the stored record.
- Risk: actor identity collisions. Mitigation: storage identity uses the same
  deterministic portable member key as Room membership.
- Risk: an unbounded UI query. Mitigation: fixed message-set and result limits
  are enforced by the capability contract and built-in engine.
- Risk: repeated commands create duplicate UI activity. Mitigation: no-op
  transitions return no Publish directive.
- Risk: reaction state mutates message history. Mitigation: reactions use a
  separate record and storage capability.

### Definition of Done

- R1 through R10 have test or gate evidence.
- No accepted design-review finding remains.
- Unit 2 is recorded complete before Unit 3 work begins.

### Planning Sources

- [Approved goal brief](./2026-11-16-1135-jido-chat-assembly-v3-goal-brief.md)
- [Completed Unit 1 plan](./2026-11-16-2045-unit-1-durable-provider-provisioning-plan.md)
- `lib/jido_chat/runtime/actions/room_command.ex`
- `lib/jido_chat/runtime/room/durable.ex`
- `lib/jido_chat/runtime/room/plugin.ex`
- `lib/jido_chat/runtime/signal/room.ex`
- `lib/jido_chat/runtime/storage/**`

## Adapter Results

- Markdown: canonical at `docs/plans/2026-11-16-1810-unit-2-durable-reactions-plan.md`
- HTML: not requested
- Beadwork: not requested

## Execution Results

- Status: complete on 2026-11-16.
- Repository start and end commit: `810ef0c265dae238d5971dc8f4ed65bab1f93892`.
  The unit remains in the local working tree. No checkpoint commit was authorized.
- Added portable revision-checked reaction records with stable Room, message,
  reaction, and actor identity.
- Added the independent Reactions storage capability, Commit commands, Memory
  and DETS support, deterministic bounded queries, and DETS format version 6.
- Added authorized Room add and remove commands, correlated replies, and
  canonical reaction facts that are published after storage succeeds.
- Added Runtime get and list functions. Durable history remains immutable, and
  threads remain a projection of `thread_id`.

## Design Review Results

The Elixir design review found three supported issues. All three are fixed:

- Reaction restore now rejects changed derived record IDs and actor keys. It no
  longer recalculates those fields and hides damaged snapshot data.
- The Runtime reaction list returns `{:error, :invalid_options}` for malformed
  options instead of raising in `Keyword` functions.
- Reaction command Signals now enforce the same byte limits as durable records.

The final review traced record construction, Signal input, authorization,
durable state changes, publication order, adapter extension contracts, DETS
restart behavior, Runtime queries, tests, and documentation. No accepted
finding remains.

## Verification Results

- Focused reaction, storage, DETS, and durable Room tests: 43 passed.
- Full package tests: 468 passed.
- Covenant: 28 tests passed and 25 of 25 obligations covered.
- Coverage: 90.4%, above the configured 90% threshold.
- `mix quality`: passed with no Credo or Dialyzer issue; Doctor passed.
- `mix docs -f html -f markdown`: completed. Existing hidden upstream callback
  reference warnings remain unchanged.
- Unused dependency check: passed.
- Compile-connected dependency graph: 170 files, 182 compile edges, zero cycles.
- `git diff --check`: passed.
