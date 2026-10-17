---
title: Public Signal Migration — Remaining Work and Completion Plan
date: 2026-10-13
status: complete; G0-G9-implementation-pass; publication-blocked
primary_plan: 2026-10-12-002-public-signal-boundary-plan.md
scope: same implementation and PR scope as the primary plan
---

User scope change — October 14: Mattermost is excluded because it is not the
user's package. The current goal covers eight adapters and ten packages. Earlier
Mattermost work and reports remain historical evidence. The user accepted the exact Cowlib/Gun findings in audit-exceptions.json.
The user approved the ten B6 pushes and review PRs. Continue through G9.
Keep the raw failed audits and preserve all other checks.

# Public Signal migration — remaining work

This document records the local analysis and the execution order.
The user authorized B0–B2, then B3, B4 and B5, on October 13. Stop after B5.
The October 12 plan remains the requirements contract. All eight adapters,
the 90 percent Messaging coverage requirement, package checks, PR review,
and current-head CI remain required. This analysis did not change gate status,
application code, dependencies, or existing test results.

## B0–B2 result

B0, B1, and B2 passed. G3 is complete. Messaging coverage is 90.05059 percent.
Both runtime profiles pass 2,006 tests. Chat passes 257 tests. Package quality,
catalog, API, and source checks pass. Execution stopped at B2.
See [the checkpoint report](../migration/CHECKPOINT_B0_B2.md).

## B3 result

G4 and G5 passed their own acceptance reports. Telegram passes 243 tests,
Slack passes 142 tests, and the B3 runtime passes 129 tests. Both package
quality gates and the 241-test shared harness pass. The frozen matrix has
two complete adapter rows. Execution stopped at B3.
See [the B3 report](../migration/CHECKPOINT_B3.md).

## State before this checkpoint

The implementation folder is `.worktrees/public-signal-v3/`. Reuse its
`codex/public-signal-v3` branches. The main checkouts contain older code.

| Item | Recorded state |
| --- | --- |
| G0: pinned dependency baseline | Passed |
| G1: contract inventories | Passed |
| G2: Chat core | Passed |
| G3: Messaging boundary | Pending; substantial implementation and tests exist |
| G4–G5: membership, Telegram, Slack | Pending; substantial preparation and package tests exist |
| G6: remaining providers | Pending |
| G7: whole-group conformance | Pending; `Conformance.run/0` is absent |
| G8–G9: package readiness and PR delivery | Pending |

Telegram, Slack, and Signal have native protocol/normalization entry points.
Discord, GitHub, Teams, WhatsApp, and X do not yet have those entry
points in these checkouts. This source check does not give any adapter final
conformance approval.

The latest saved complete Messaging runs passed 1,953 tests in each runtime
profile. The latest inclusive coverage report is 87.2 percent. Four optional AI
fixtures and 241 runtime harness checks are also recorded as passing.

The next unfinished change is
`jido_messaging/test/jido_messaging/route_result_resource_test.exs`.
It is untracked. Core has 16 related untracked evidence files. A later focused
run records 129 passing tests after earlier failures. Compare the saved source
hashes with the current file before treating that result as current proof.

## Why progress has been slow

The evidence period is October 12, 11:15 a.m., through October 13, 6:52 a.m.,
America/Chicago. This is a record span, not a measurement of continuous work.

| Local measure | Result |
| --- | --- |
| Files under `docs/migration/evidence/` | 2,482 |
| Timed command records across gates | 1,148 |
| Timed G3 command records | 918; 193 have a nonzero exit status |
| Complete Messaging suite commands in G3 | 88; summed command duration 89.8 minutes |
| Coverage suite commands in G3 | 50; summed command duration 84.6 minutes |
| G3 quality commands | 99; summed command duration 29.1 minutes |
| All timed G3 commands | Summed command duration 327.9 minutes |
| Chat commits from the migration baseline | 70, including 56 documentation commits |
| Messaging commits from the migration baseline | 115, including 66 fixes and 40 test commits |

Counts use the actual command arguments. Selected tests and audit commands are
not counted as complete suites or coverage suites. Summed durations can include
overlap. They do not measure agent reasoning or documentation time. A failed
command record is not necessarily an unresolved defect; later fixes and tests
can replace it.

The records support five causes:

1. **The requested change is large.** It spans two libraries, eight adapters,
   110 native definitions, 26 operations, resources, identity, authorization,
   storage, transport acceptance, and two runtime profiles.
2. **G3 has no finite remaining task list.** Its record has 271 completed
   entries. Its remaining entries still say to finish broad ownership/failure
   work and all G4–G9 work.
3. **The tracker mixes prerequisites with later work.** G3 lists G4–G9
   completion as remaining G3 work. The primary plan makes those gates depend
   on G3. Following both rules cannot produce a useful G3 completion decision.
4. **Whole-package coverage directs work into many subsystems.** Coverage
   increased from 73.8 to 87.2 percent. This added useful proof and found real
   faults. It also expanded the work beyond the central Signal path. The
   remaining gap needs a fixed test list, not another general review.
5. **Checks and records repeat after small changes.** Recent complete suites
   take about 37 seconds each. Repeating suites, graphs, audits, quality checks,
   and evidence updates after each small change adds substantial work.

The files cannot show which repeated runs were unnecessary. The assessment is
that open completion criteria and frequent broad checks are major sources of
delay. The large number of fixes also shows that this was not all wasted work.

## Execution rules

- Use one row per remaining task: ID, exact behavior, files, check, state,
  and evidence. Allowed states are pending, running, pass, fail, or blocked.
- A task must name an observable behavior. Do not use "more ownership proof"
  or "finish hardening" as a task description.
- Reuse passing proof when the relevant code, tests, graph, and configuration
  are unchanged. Record why it remains valid.
- After a code change, run its focused tests. Run the full required checks
  once at batch completion. A failure or a later relevant change requires a
  rerun of the affected checks.
- Keep the existing small, tested progress commit rule. Record checks and open
  work in those commits. Do not create a new documentation commit for every
  unchanged graph or repeated successful check.
- For each completed batch, save one current report with source hashes,
  command results, and links to logs. Keep existing historical evidence.
- Freeze passed interfaces and dependency refs. Change them only for a recorded
  defect or a failed required check.
- Execute sequentially. This document does not authorize agent delegation.

## Completion batches

### B0 — Save the unfinished work and make the tracker usable

1. Compare the route result test and relevant sources with the latest passing
   `g3-route-result-resource-owned-tests.json` and quality record.
2. Inspect the earlier failures and the later test changes. Keep assertions
   for complete results, exact callback counts, owned resources, and cleanup.
   If the current source differs, rerun the affected focused tests.
3. Save the verified test change and its current evidence in focused commits.
4. Build the G3 acceptance table below from existing proof. Each row must be
   pass, missing-proof, or fail. A missing-proof/fail row becomes one exact task.
5. Separate each gate's own tasks from later gates in the tracker. Keep the
   90 percent coverage requirement as an explicit G7 requirement, as specified
   by the primary plan. Its work is scheduled in B2, before adapter completion.

**Complete when:** the unfinished change is saved, the seven G3 acceptance rows
are classified, and no gate lists its dependents as its own prerequisites.
Do not mark a gate passed only because its tracker was corrected.

### B1 — Close the Messaging contract step, G3

Use these finite acceptance rows. Inspect existing tests before adding tests.

| ID | Required result | Existing proof to inspect |
| --- | --- | --- |
| R1 | Bus requests and denied/failed authorization cause zero provider calls | `typed_execution_test.exs`, `authorization_test.exs` |
| R2 | Retry, broadcast, failover, and admission keep exact callback counts | `typed_request_admission_test.exs`, `outbound_router_test.exs` |
| R3 | Publication failure cannot repeat accepted work or retain an unpublished result resource | `provider_result_publication_test.exs`, `route_result_resource_test.exs`, `local_post_resource_failure_test.exs` |
| R4 | Accepted parent facts are unchanged; children keep trace and direct causation | `typed_acceptance_test.exs`, existing native integration fixtures |
| R5 | Source/subject selection isolates rooms; thread policy stays in the application | `typed_room_subscription_test.exs`, existing Telegram/Slack integration fixtures |
| R6 | Both pinned runtime profiles and optional AI fixtures pass | Current complete core/AI profile records and optional AI record |
| R7 | One native public path remains; the API audit and prohibited-boundary scan pass | Current compiled API audit and G3 source scan |

Repair only a failed row or a concrete defect found in this bounded review.
Use the current runtime/facade/storage ownership note to check those rows.
Do not turn its broad wording into a new whole-package review.

**Complete when:** R1–R7 pass on the applicable candidate sources. Record G3
against its own contract. Later adapter, coverage, packaging, and PR tasks remain
visible in their own batches.

### B2 — Meet the Messaging coverage requirement

The latest saved coverage table has 12,452 relevant lines, 10,863 covered lines,
and 1,589 missed lines. With that fixed denominator, 344 additional covered
lines reach 90 percent. About 407 reach 90.5 percent. These are planning
calculations, not a guarantee: production changes can alter the denominator.

Use the saved `cover/cov.coverdata` to assign actual missed lines to behavior
tests. Do not rerun the entire suite to find the same gaps repeatedly.

| Batch | Files and fixed behavior targets | Current missed lines |
| --- | --- | --- |
| T1 | `execution.ex`: large route/provider results, invalid request metadata, and failed result construction/cleanup | 28 |
| T2 | `jido_messaging.ex`: resource lookup defaults, directory/onboarding wrappers, disabled bridge selection, assignment/runner failure results, outbound route wrapper | 89 |
| T3 | `persistence/ets.ex`, `persistence/sqlite.ex`: binding conflicts/revocation, deterministic binding race outcomes, empty/missing reads, delete scope, migration failure cleanup | 146 |
| T4 | `bridge_registry.ex`, `adapter_bridge.ex`: malformed manifests, capability/adapter parsing, required bridge diagnostics, outbound/media cleanup | 73 |
| T5 | `ingest.ex`, `demo/topology.ex`, `outbound_gateway/partition.ex`: admission/partial effects, complete scoped topology, gateway selection/retry failures | 113 |

These files have 449 missed lines in total. They are candidates, not a demand
to cover every missed line. Use public behavior and state/callback assertions.
Do not add tests that only mirror implementation. Do not change coverage
exclusions or thresholds. Do not introduce production hooks just for coverage.

1. Finish T1 and include the already prepared route result tests.
2. For T2–T5, select named behaviors and line IDs before coding. Cover the
   largest meaningful gaps first. Use process barriers for concurrency cases.
3. Run focused tests per change. Measure combined coverage after each completed
   test batch. Stop coverage work when the required floor passes.
4. If these candidates cannot reach the floor, publish one finite remaining
   behavior list with the measured deficit. Do not resume a general audit.
5. At batch completion, run the inclusive Messaging suite, both runtime
   profiles, required quality checks, and optional AI fixtures on the candidate.

**Complete when:** required inclusive coverage is at least 90 percent and the
named package/runtime checks pass. Chat and Messaging then have a concrete
implementation checkpoint. Whole-group completion still requires B3–B6.

### B3 — Finish membership and the first adapter pair, G4–G5

Reuse existing Telegram and Slack code and proof. Close these named gaps:

1. Check each declared event/operation fixture against the frozen matrix.
   Existing 26-operation reports are inputs; missing rows are exact tasks.
2. Check Slack Socket sink error, raise, throw, exit, and invalid return behavior
   against its declared acknowledgement order.
3. Check Slack modal conversation scope and private token/resource lifetime.
4. Complete both adapters' event/resource/interaction and transport rejection
   rows. Use complete deliveries, exact sink/callback counts, and checkpoint
   assertions. Retain existing live-test exclusions only.
5. Reuse existing membership isolation tests. Refresh them only for affected
   sources. Match every G4 membership condition to a named assertion.

**Complete when:** G4 and G5 each have their own passing acceptance report.
Do not make their pass state depend on G8 or G9.

### B4 — Finish the remaining provider contracts, G6

Use this order from the primary plan: Discord, GitHub, Signal final conformance,
Teams, WhatsApp, X. Signal already has its native mapper; assess its
remaining rows before changing it.

For every provider, complete the same six-row checklist:

1. Protocol startup and captured configuration.
2. Declared event mapping; zero/one/many item order and stable identity.
3. All declared operation results, native/fallback/unsupported behavior.
4. Query/stream/resource and private control behavior.
5. Acceptance, rejection, acknowledgement/checkpoint, and retry behavior.
6. Package tests, required quality/coverage, and provider-specific assertions
   from the primary plan.

Do not add a new provider shape or change support claims to avoid a failed test.
Return a completed matrix row after each provider. This is seven finite signoff
units, including six adapters that still need native entry points.

**Complete when:** all eight adapter rows are implemented and locally verified.

### B5 — Run one complete acceptance report, G7

Implement `Jido.Chat.Integration.Conformance.run/0` with explicit C01–C14 results.
Connect existing fixture/test proof where it checks the actual assertion.
Do not return pass from test counts or manifest presence alone.

Resolve and test the full eight-adapter graph. Freeze candidate source hashes.
Run whole-group conformance, applicable package suites/quality/coverage, both
runtime profiles, graph checks, and the full prohibited-boundary scan.

**Complete when:** every C01–C14 row and every required package check passes.
After a failure, rerun the affected checks. Refresh the full report before final
delivery if a source change affects it.

### B6 — Package and deliver, G8–G9

Finish the migration guide, runnable examples, version proposals, production
dependency metadata, package file lists, builds, release order, and rollback pins.
Record external unpublished-dependency blockers separately.

Review the candidate changes. Fix actionable defects. Push the verified branches
and open/attach one focused PR per changed repository. Check CI on the current
PR heads and record the final PR/evidence index. Merges, publication, and live
provider operations remain outside this goal.

**Complete when:** G8 and G9 meet the primary plan. All requested implementations
must be delivered; named external release availability can remain a publication
blocker under the existing G8 rule.

## Work report at each batch end

Report only the decision data: batch ID and result, completed acceptance rows,
exact open defects, current coverage and measured deficit, adapter rows passed,
saved commit IDs, and the next batch. The report must show what is still required
to finish. Do not use command count or commit count as a completion percentage.

B0–B4 are complete. G0–G6 pass. B5 checks are finished. G7 failed. Execution
stopped after B5. B6 did not start. Later execution requires a new user instruction. See
[the B4 report](../migration/CHECKPOINT_B4.md) for results. The current records
do not support a reliable total time estimate.


## B4 result — October 13

G6 passed. All nine adapter rows are implemented and locally verified. The seven
remaining package quality checks pass. Mattermost coverage is 91.5 percent;
WhatsApp coverage is 80.8 percent. All 382 G6 fixtures and 129 refreshed B3 fixtures
pass. All 297 original literal case names remain. Code and evidence are saved in
local commits. Execution stopped after B4. B5 and B6 did not start. G7–G9 remain
pending. See [CHECKPOINT_B4.md](../migration/CHECKPOINT_B4.md).

## B5 result — October 13

C01–C13 pass. C14 fails because the Mattermost package build fails. All required
checks have results. The full graph and Discord audits fail on Cowlib and Gun.
Mattermost has no license, as the user specified, and Fresh remains a Git
dependency. No exception was accepted. All package suites, mix quality checks
and coverage floors pass. The local index has all 11 candidates; PR delivery
remains in B6 by user selection. Tested changes are saved in local commits.
Execution stopped after B5. G7 has not passed. B6 did not start.
See [the B5 report](../migration/CHECKPOINT_B5.md).

## October 14 current result

G7 passes for eight adapters and ten packages with the exact accepted audit
exception. G8 implementation readiness passes with named upstream release
blockers. B6 is completing the ten PRs and current-head CI.
See CHECKPOINT_B5_SCOPE_UPDATE.md and CHECKPOINT_B6.md in docs/migration.

## B6 completed — October 14

All ten review PRs are open and attached. G7 and G9 pass. G8 implementation
readiness passes with named upstream publication blockers. Required suites,
coverage, package builds, both profiles and CI pass. Stop after B6.
See docs/migration/CHECKPOINT_B6.md and the workspace delivery index.
