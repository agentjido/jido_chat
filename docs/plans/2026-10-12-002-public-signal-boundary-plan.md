---
title: Jido Chat and Messaging — Public Signal Migration
date: 2026-10-12
status: B3-checkpoint-complete; G0-G5-pass; G6-G9-pending
scope: implementation and reviewable PRs; release execution excluded
issues:
  - https://github.com/agentjido/jido_chat/issues/57
  - https://github.com/agentjido/jido_chat/issues/58
upstream:
  catalog: https://github.com/agentjido/jido_signal/pull/216
  bus_context_filters: https://github.com/agentjido/jido_signal/pull/217
  dependency_fix: https://github.com/agentjido/jido_signal/pull/218
signal_baseline: d6611eca1c95eb507843baceb55991e4801d8421
---

# Jido Chat and Messaging — Public Signal Migration

## Goal contract

Implement one typed public communication contract across `jido_chat`,
`jido_messaging`, and all nine active provider adapters. Use Jido Signal v3
custom definitions for events, commands, queries, and results. Complete normalized
membership support from #57 as the first feature. Remove obsolete event wrappers
and duplicate routing from the new release line. Deliver tested, reviewable PRs
and a reproducible integration report.

This document is the primary plan. It supersedes the September 25 all-Chat
namespace proposal and the October 12 compatible-1.x alternative. The source
investigation and upstream assessment remain references; they do not override
this contract.

The user has selected Signals as the public boundary and has refined Bus
selection to type, source, and subject only. This refresh prepares the goal;
it does not create or start a goal, change application code, or authorize merges
or releases.

Suggested future goal objective:

> Execute this plan through gates G0–G9. Implement the typed public Signal
> contract, normalized membership support, and all nine adapter migrations.
> Use one pinned compatible v3 dependency graph. Run the specified checks and
> open PRs with exact evidence. Finish only when every gate passes. Do not merge,
> publish packages, perform live provider operations, or change the agreed scope.

Default completion is implementation plus PRs, not production deployment.
A failed prerequisite is not completion. Do not replace the selected v3 APIs
with a local catalog or a broader Bus filter to bypass a failed gate.

## Current facts and prerequisites

Checked on October 12, 2026:

| Item | Current state | Required treatment |
| --- | --- | --- |
| Signal catalog, PR #216 | Merged as `ba1314f4f9607ead6c22784dd2f8aa50b0502e12` | Use the accepted v3 catalog; do not duplicate it in Chat. |
| Bus filters, PR #217 | Merged as `d6611eca1c95eb507843baceb55991e4801d8421` | Type path plus exact source/subject equality via `selector:`. No payload or callback filters. |
| Decimal fix, PR #218 | Merged into `release/v3` | Keep the fixed dependency in the pinned baseline. |
| Signal `release/v3` | Pinned baseline `d6611eca1c95eb507843baceb55991e4801d8421`; CI passed on that exact head | Use this immutable ref for the initial goal run. A later ref requires fresh evidence. |
| Chat/Messaging workspace | Local checkouts behind origin; plan files are untracked | Preserve local files and create isolated implementation branches from verified bases. |
| Messaging dependencies | Jido/Signal v2 requirements; optional Jido AI integration | Migrate the dependency contract before treating Signal v3 as usable. Test with and without the optional AI integration. |
| Jido AI `release/v3` | Branch uses v3 Git refs but still declares version 2.3.0 | Record source commits and dependency graph, not only the declared package version. |
| Integration lab | Local folder has no Git repository and omits WhatsApp | Put the final deterministic harness in a versioned dev-only core subproject. |

The original combined 524-test run used the broad selector version that was
subsequently removed. It is historical evidence only. It does not validate the
refined source/subject implementation or any Chat/Messaging migration.

**Upstream preparation check: PASS.** Both final feature commits are in the
pinned branch head, along with Decimal 3.2.0 and Zoi 0.18.11. The
[head CI run](https://github.com/agentjido/jido_signal/actions/runs/38273181437)
passed compile, tests on OTP 27/28/29 and Elixir 1.18/1.19/1.20 combinations,
audit, Dialyzer, Credo, format, docs, unused dependencies, and package dry run.
The experimental compile and changelog guard jobs were skipped by that workflow;
they are not reported as executed tests.

This is readiness to start the goal. G0 still owns the Chat/Messaging consumer
dependency graph and optional-AI checks; those have not been executed. The local
Signal checkout was clean but behind the remote by three commits at this check.
Fetch and use the pinned source in isolated goal checkouts. Do not run against
the older local head or infer feature availability from the beta version string.

## Frozen scope

| Package | Responsibility |
| --- | --- |
| `jido_chat` | Shared typed definitions, configured bindings, provider operation boundary, normalization/delivery values, lightweight signal handlers, shared conformance kit. |
| `jido_messaging` | Direct ingress acceptance, identity resolution, authorization, records, routing/retry ownership, runtime signals, instance Bus, optional AI integration migration. |
| Discord, Slack, Telegram, GitHub, Signal provider, Mattermost, Teams, WhatsApp, X | Provider verification, mapping into shared Chat signals, private transport operations, declared capabilities. |

Use `Jido.Chat.Signal.*` for provider facts and operations and
`Jido.Messaging.Signal.*` for runtime facts and requests. Keep separate
`jido.chat.*` and `jido.messaging.*` wire namespaces. Retain existing Messaging
type names where their meanings remain correct; version the new data schemas.

The Signal provider owns the parent `Jido.Chat.Signal` module. Core defines
child modules only. Use upstream `Jido.Signal.Catalog` directly with an explicit
list of domain definitions. Do not introduce a second generic catalog wrapper.

Exclude `jido_chat_ui`, showcase application changes, new providers, a new durable
inbox/outbox design, credential/grant administration, and a general callback
framework. Do not change Amarula to another WhatsApp technology in this work.
Do not modify `CHANGELOG.md`.

Published incompatible Chat/Messaging APIs target their next major release
(currently proposed 2.0.0). Decide each adapter version from its actual public
change and publication history. Use no permanent legacy mode in the new line.
Old consumers can pin the released 1.x line and use the migration guide.

## Public interface and data rules

The following signatures are the target contract. Exact option names and error
modules are recorded in the G1 API manifest before other units depend on them.

```elixir
{:ok, binding} = Jido.Chat.bind(adapter, binding_options)
{:ok, request} = Jido.Chat.Signal.SendMessage.new(request_data)
{:ok, result_signal} = Jido.Chat.execute(binding, request)
{:ok, delivery} = Jido.Chat.normalize_event(binding, provider_request)
{:ok, acceptance} = Jido.Messaging.accept_delivery(instance, delivery)
{:ok, result_signal} = Jido.Messaging.execute(instance, runtime_request, trusted_actor_options)
```

Queries use the same direct execution boundary. A completed operation or a
provider failure returns a registered result Signal. Invalid input/setup returns
one documented structured contract error. Execution must call the provider once
per logical request, except existing explicit retry/failover policy.

A configured binding hides transport selection, credentials, and resource
resolution. Ordinary callers do not supply transport modules, callback MFAs,
bus names, or credential lookup on every request. Signals carry operation data;
trusted execution context carries authority and resources.

Normalization produces one small delivery value: stable delivery identity and
an ordered list of zero, one, or many validated Signals. Transport responses and
private resources are separate. A delivery container is not another event model.
All items are validated before authoritative processing starts. Item failures
use a registered `NormalizationFailed` fact. A contract size/count limit breach
rejects the delivery before processing; it must not silently drop work and
acknowledge the provider.

Signal data uses string keys and Zoi schemas that support lossless JSON round
trips. Select fields explicitly. No raw provider maps, credentials, client objects,
PIDs, functions, local paths, bytes, or lazy streams occur in public signal data.
Use scoped resource references for files, streams, and large results. Resource
expiry, failure, cancellation, and ownership are tested. No restart-safe replay
is claimed for a call-local reference.

Initial safety limits are 256 KiB per encoded Signal, 1 MiB per normalized
provider delivery, 100 Signals per delivery, and 20 item-failure Signals. G1 records
these values and their exact rejection errors; tests cover the boundary and one
value beyond it. Do not truncate message text to satisfy a limit.

Use native v3 Trace/Context helpers for W3C trace propagation. Put the direct
parent Signal ID in an approved flat `causationid` context field. Delivery/item
identity and command idempotency remain separate fields. Do not restore the v2
custom correlation extension. Never change an accepted adapter parent to add
runtime identity; construct a causally linked runtime child.

## Bus and context identity contract

Your latest Bus scope is authoritative:

- `type`: existing exact and wildcard Signal type routing.
- `source`: optional exact equality.
- `subject`: optional exact equality.
- All supplied conditions must match.
- Omitting a context filter leaves that attribute unconstrained. A requested
  subject that is absent does not match. Invalid configuration fails explicitly;
  it must not silently become an unfiltered subscription.
- No data/extension filters, arbitrary predicates, or application callbacks in Bus.
- Ordinary subscriptions only initially. Reject filtered durable subscriptions.
- Compile source/subject matching once at subscription registration and use Router
  selection and direct Signal pattern matching.

The final option syntax from PR #217 is:

```elixir
Jido.Signal.Bus.subscribe(bus, "jido.messaging.room.message_added",
  selector: [source: instance_source, subject: room_subject]
)
```

The keyword list accepts source, subject, or both exactly once. Values are
non-empty strings of at most 4,096 bytes. Source must be a URI-reference; subject
must be valid CloudEvents context text. Empty/nil selectors, duplicate outer
options or field keys, other fields, functions, and MFAs fail before subscription
state is added. The earlier map-path `selector:` interface is not this API.
G0 verifies these committed semantics with the pinned source.

G1 freezes the following domain meaning for metadata:

| Signal owner | Source | Subject |
| --- | --- | --- |
| Adapter conversation facts | Stable opaque adapter binding source | Stable primary room/conversation key, scoped by the binding. |
| Messaging room facts | Stable opaque Messaging instance source | Canonical room key. |
| Membership observation with unresolved room | Messaging instance source | Absent; retain the external reference in validated data and reference the parent. |
| Commands/queries/results and non-room facts | Explicit producer/target rule in each catalog entry | Exact rule for the operation/resource, including permitted absence. |

Do not place room IDs into semantic type names. Use one helper per domain owner
for source/subject construction, with fixed encoding and fixtures in G1. The
helper must distinguish binding and instance scopes and must not invent canonical
identities. Source/subject contain no credentials or transient provider tokens.

For conversation events, choose room-level subject consistently. A thread ID,
actor, text, role, or numeric condition remains domain data. Thread and agent
policy is evaluated in the application after the context subscription. Do not
try to express payload policy through the Bus.

Tests must show two bindings with the same external room ID remain distinct;
two rooms in one instance remain distinct; and a rename does not change identity.

## Use v3 primitives and keep domain ownership

| Primitive | Use |
| --- | --- |
| Signal definitions/Catalog | Shared schemas, exact definition lookup, identity-preserving validation/decoding. |
| Router and compiled DSL | Configurable type handler selection; static routes reference Signal modules. |
| Dispatch | Ordered synchronous observation delivery through native targets; optional Phoenix bridge carries the same Signal. |
| Instance Bus | One observation/subscription surface after direct acceptance. |
| Trace/Context and telemetry | Causation, bounded diagnostics, and test observations. |

This plan targets v3. It does not depend on v2 Bus middleware, BusSpy, parallel
Dispatch fan-out, persistent-subscription retry/DLQ machinery, or custom extension
policies. Use v3 telemetry or ordinary test subscribers for observation.

Router returns matching targets; a small runner owns state and handler invocation.
It does not replace authorization or Messaging broadcast/failover policy.
Dispatch success is not a provider domain result. Bus publication is not provider
acceptance. A Bus-published request cannot invoke a provider callback.

Keep provider subscription provisioning distinct from Bus subscriptions.
Preserve current acknowledgement/checkpoint timing and declared memory-mode
behavior. Bus Store/replay does not replace Messaging transactional delivery.
No exactly-once provider-effect or atomic multi-record database guarantee is added.

## Required finite inventories

G1 creates checked, versioned manifests. They are part of the core PR.

1. **API map:** every old communication API has one new request/result or an explicit
   retained-domain-value classification. No unclassified export remains.
2. **Catalog:** exact module, type, dataschema, owner, kind, data schema, source rule,
   subject rule, allowed context fields, and valid fixture for each entry.
3. **Operations:** the 26 existing provider operation callbacks, their capability,
   native/fallback selection, typed result variant, and resource rules. Lifecycle,
   verification, listener setup, and capability lookup are classified separately.
4. **Adapter matrix:** all nine adapters; exact event/operation support, membership
   support, participant-query support, transport/delivery identities, acceptance,
   acknowledgement/checkpoint, and retry unit.
5. **Version matrix:** exact source commits, branches, dependency versions/refs,
   publication state, test environment, intended new package version, and rollback pin.

Operation inventory: send_message, send_file, post_message, edit_message,
delete_message, start_typing, fetch_metadata, fetch_thread, fetch_message,
get_user, fetch_subject, get_thread_participants, mark_as_read, fetch_media,
add_reaction, remove_reaction, post_ephemeral, post_channel_message, stream,
open_modal, load_options, fetch_messages, fetch_channel_messages, list_threads,
open_thread, and open_dm. Provider convenience aliases and subscription/pairing
extensions must have an explicit classification; no generic execute-anything escape.

Initial Chat facts include received/updated/deleted messages, reaction add/remove,
actions, modal submit/close, options requests, slash commands, assistant thread/
context facts, membership, thread start, receipts, and normalization failures.
Runtime facts include room/message/participant/thread state, presence/typing,
agent/instance lifecycle, membership observation, and selected runtime request/results.
Use common OperationCompleted/OperationFailed definitions with a closed,
operation-specific result union. Stored records and content builders remain records
and input helpers; they are not another communication envelope.

## Execution order and gates

Every gate has a binary result and recorded evidence. Run prerequisites first.
Preparatory independent work is allowed while a prerequisite is unresolved, but
G2–G4 pass status requires the G0 baseline. Do not expand upstream or product
scope when a gate fails.

Initial planning state on October 12: G0–G9 were pending.
Current state is in `docs/migration/gate-status.json`. G0–G3 now pass.
The user-authorized B0–B2 checkpoint is complete; execution stopped there.
The upstream source prerequisite is verified. It is not a completed consumer
dependency or Chat/Messaging migration gate.

| Gate | Depends on | Main implementation targets |
| --- | --- | --- |
| G0 | Accepted upstream v3 source | Package manifests/locks and version matrix; no core library fork. |
| G1 | G0 | Core `docs/migration/` manifests and `integration/` dev project/gate script. |
| G2 | G1 | `lib/jido_chat.ex`, `lib/jido/chat/adapter.ex`, typed definitions under `lib/jido/chat/signal/`, binding/execution/normalization helpers, shared test kit. |
| G3 | G2 | Messaging `inbound_router.ex`, `ingress_sink.ex`, `events.ex`, `signal.ex`, `dispatch.ex`, `agent_runner.ex`, ChatActions/AdapterBridge/gateway integration, optional AI tests. |
| G4 | G2 and G3 | Membership definitions/handlers, Telegram adapter/update envelope/polling, Messaging membership ingress tests. |
| G5 | G4 | Telegram and Slack adapters/listeners; core integration scenarios. |
| G6 | G5 | Remaining seven adapter source/test/docs files and package constraints. |
| G7 | G6 | Versioned all-adapter harness and final candidate-source matrix. |
| G8 | G7 | Migration guide, package metadata/file lists, examples, version and release-readiness matrix. |
| G9 | G8 | Verified commits, PR index, current-head CI and final evidence bundle. |

### G0 — Reproducible v3 baseline

**Work:** inspect origin and preserve local changes. Record source SHAs. Create
isolated branches. Use Signal v3 commit
`d6611eca1c95eb507843baceb55991e4801d8421`, which contains catalog decoding,
the refined type/source/subject Bus API, and the Decimal fix. Select compatible
Jido/Jido Action refs; prove optional Jido AI compatibility separately.

**Pass:** a clean dependency graph resolves one Signal and one Zoi version; no
v2 runtime package is forced into a v3 test. Package compile and existing baseline
suites pass. A smoke test constructs/JSON-decodes a typed catalog Signal and
subscribes using type/source/subject. Invalid payload/callback filters and filtered
durable subscriptions are rejected. Record both core-only and optional-AI graphs.

**Evidence:** `docs/migration/version-matrix.json`, baseline command logs, and
exact upstream refs. Published beta.4 without the new commits fails this gate.
Unmerged refs can be used for local feasibility only; final delivery needs a
stable upstream ref containing the accepted changes. A dependency override alone
is not evidence of compatibility. Do not claim a new package version is published.

### G1 — Frozen contract and runnable gate harness

**Work:** write the five inventories and migration guide skeleton. Choose retained
record/builders and remove-wrapper list. Freeze source/subject encoding, protocol
version 1, limits, result/errors, and handler precedence. Put the deterministic
lab in `jido_chat/integration/` as a separate dev-only Mix project. It uses the
version matrix to resolve the nine adapter sources. Do not ship it in the Hex
package or change runtime dependency direction.

**Pass:** all nine adapter entries and all 26 operations are classified. Every
catalog type has one schema identity and fixture. All public communication APIs
have a mapping. No duplicate definition pair exists. The harness checks manifest
completeness and the domain rules below and emits structured pass/fail output.

**Evidence:** `api-map.json`, `catalog.json`, `adapter-matrix.json`, and
`gate-status.json` under `docs/migration/`. The versioned harness replaces reliance
on untracked local lab changes. Its gate script does not exist yet; implement it
in this unit.

### G2 — Core public boundary

**Work:** implement domain definitions, configured bindings, one executor, delivery
normalization, and Signal handlers. Use upstream Catalog. Extract private callback
invocation/fallback logic. Remove EventEnvelope/DTO/result projections from the
new public path. Keep useful domain records/builders and only justified helpers.

**Pass:** every registered fixture survives build → JSON → catalog validation.
All 26 operation mappings have a valid/unsupported/failure test. Typed request
execution invokes exactly the selected callback once. Old wrappers are absent
from the new API map. Limits and resource lifecycle tests pass. Core and the
Signal provider compile together without a duplicate parent module.

**Evidence:** core tests, protocol/schema fixture report, operation report, and
an empty prohibited-boundary scan.

### G3 — Messaging public boundary and ownership

**Work:** accept Chat deliveries directly, without a temporary Chat handler loop.
Use one runtime catalog/emission path and one instance Bus. Migrate direct runtime
requests, AgentRunner consumers, optional AI examples/tests, and Signal metadata.
Retain existing identity, authorization, routing, retry, and record ownership.
Remove legacy tuple event mirrors and duplicate public subscription paths.

**Pass:** Bus requests and authorization denial/store failure cause zero provider
calls. Existing retry/failover/broadcast scenarios preserve their intended counts.
Publication failure does not rerun an accepted operation. Parent facts remain
unchanged; child facts have the correct trace and causation. Core-only and optional
AI integration suites pass against the G0 graph. Room context selection follows
source/subject rules; thread and trigger policy remains in application code.

**Evidence:** runtime tests, side-effect-count report, observation/authorization
report, optional-AI report, and prohibited-boundary scan.

### G4 — Membership feature from #57

**Work:** build MembershipChanged and MembershipObserved. Add standalone typed
handler registration and a dedicated Messaging branch. Implement Telegram
chat_member/my_chat_member webhook and polling normalization. Validate incomplete
Slack transitions against the same schema; finish native Slack mapping in G5.

**Pass:** join/leave/removal evidence, role/restriction change, bot-self, missing
actor, and unavailable previous state pass fixtures and JSON round trips. Restricted
Telegram membership respects is_member. No membership fact enters message/mention
handlers, agent message triggers, or modifies grants, runtime membership, or
presence. Sink rejection prevents the tested checkpoint advancement. Repeated
provider updates produce one semantic observation under the declared memory rule.
Participant queries have a separate capability; no partial set is labelled complete.

**Evidence:** shared membership fixtures, Telegram transport tests, Slack schema
fixtures, state-before/state-after assertions, and a #57 completion report.
Do not close #57 until its revised acceptance scope is agreed with its submitter.
Issue closure is not required for this gate's technical completion.

### G5 — First complete adapter pair

**Work:** finish Telegram and Slack across events, commands, queries, interactions,
resources, and transport acceptance. Share one mapper per input protocol form.
Keep transient interaction tokens in private context. Verify source/subject-only
Bus selection with the actual upstream API.

**Pass:** each adapter passes every declared shared event/operation fixture;
unsupported features produce typed unsupported results. At least one send, paged
query, interaction response, and membership path completes through Messaging.
Two bindings/rooms isolate observations correctly. Mismatched source or subject
selects nothing. Payload conditions remain application tests.

**Evidence:** two completed rows in the conformance matrix and cross-package
round-trip reports. No credentials or real provider traffic are used.

### G6 — Remaining seven adapters

**Work:** migrate Discord, GitHub, Signal provider, Mattermost, Teams, WhatsApp,
and X in that order. Independent adapters can run in parallel only when execution
is explicitly authorized to delegate. Each has an isolated checkout. Reuse G5
contracts rather than adding provider-specific public shapes.

**Pass per adapter:** declared event and operation fixtures pass; normalizer accepts
zero/one/many items and preserves order; delivery identities are stable; verification
and controls remain private; native/fallback/resource behavior passes; the transport
matrix is complete. Membership is native only for verified semantics, otherwise
explicitly unsupported. All seven package-local quality checks pass.

**Provider-specific assertions:** Teams retains all members/reactions and separates
message update/delete; X retains every DM item; WhatsApp accepts a complete upsert
unit and handles sink rejection; Mattermost and Signal normalize before the sink;
GitHub retains provider lifecycle distinctions; Discord uses conversation membership
rather than treating all guild role changes as conversation membership.

**Evidence:** all nine matrix rows complete, with per-adapter command logs and
fixture counts. No row can pass by skipping a supported feature.

### G7 — Whole-group deterministic integration

**Work:** run the versioned harness against exact candidate commits and pinned
dependencies. Exercise all common contracts and an unrelated non-chat family for
upstream generic assumptions. Do not recreate broad Bus selectors or middleware.

**Pass:** every condition in the assertion table below passes, all package tests
and required quality/coverage checks pass, and no new test is hidden behind a live
or skip tag. Optional live tests remain excluded. Each native/unsupported matrix
claim has a matching assertion. No mixed Signal major is present.

**Evidence:** machine-readable integration result, per-package verification rows,
coverage outputs, dependency graph, and empty prohibited-boundary scan. The exact
source tree and dependency refs accompany every successful result.

### G8 — Migration and package-readiness evidence

**Work:** complete public docs, consumer mapping, dependency constraints, package
version proposals, publication order, and rollback pins. Build each publishable
package and verify its file list. Test core helpers and optional Phoenix transport
only where retained. Remove stale references to v2-only Signal features.

**Pass:** no accidental path dependency or source cache occurs in a publishable
package. If a required compatible release is unavailable, name that release blocker;
do not fake a clean Hex resolution. Exact approved Git refs may support review
and tests, but release readiness remains explicitly blocked. New API examples run
in the harness. Protocol startup rejects incompatible adapters before listeners start.

**Evidence:** migration guide, package build results, release-readiness matrix,
and precise consumer pin/migration decisions. Published readiness is separate from
implementation readiness. A release blocker does not invalidate verified code,
but it must appear in the final report.

Use pinned source refs or validated dev/test-only path overrides for cross-package
tests while new package versions are unpublished. Keep intended release constraints
in the release-readiness matrix. G8 cannot pass with a source error, a bad package
file list, or an unexplained build failure. It can pass as an implementation gate
with `publish_ready: false` only when the remaining blockers are named external
release availability and the corresponding metadata/file-list checks are complete.
Do not claim a failed package build passed or publish those test overrides.

### G9 — Reviewable delivery and goal completion

**Work:** review the final diffs; commit verified trees; push one focused branch per
changed repository and open/attach its PR. The core PR includes the versioned
integration harness and plan/evidence artifacts. Keep unrelated package changes
separate. The private original lab needs no invented upstream repository.

**Pass:** all implementation gates G0–G7 pass; G8 is complete with either verified
release readiness or named external release blockers. Every required change is in
a PR, CI passes on current heads, no actionable review defect remains, and G7
reports those exact source trees. No requested adapter or contract remains unimplemented.

**Evidence:** PR index with repository, URL, head SHA, base, CI state, related issue,
and evidence hash. Final report distinguishes code-ready from publish-ready.
Do not mark the goal complete merely because PRs exist or one adapter works.

## Deterministic assertion table

| ID | Required result |
| --- | --- |
| C01 | Every catalog fixture has exact type/dataschema identity and lossless JSON validation. |
| C02 | Unknown type/schema, malformed context, unsafe data, and constructor override attempts fail without raw fallback. |
| C03 | Delivery zero/one/many order, mixed item failures, size/count rejection, and sink rejection match the declared transport rule. |
| C04 | Duplicate provider item and request fixtures have the expected record/callback/observation counts in memory mode. |
| C05 | Unauthorized, failed-authorization-store, and Bus-published commands cause zero provider callbacks. |
| C06 | Every one of the 26 operation mappings proves native/fallback/unsupported result behavior. |
| C07 | Paged queries retain items/cursors; streams remain lazy; resource expiry/cancel/failure has a typed result. |
| C08 | Accepted adapter facts are unchanged; runtime children preserve the trace and direct parent causation ID. |
| C09 | Membership evidence produces zero message-handler, agent-trigger, grant, runtime-membership, and presence mutations. |
| C10 | Type/source/subject selection isolates contexts, uses conjunction, preserves identity/order, and rejects payload/callback filters. |
| C11 | Handler precedence, broadcast/failover, retry ownership, and provider checkpoints have explicit expected counts/order. |
| C12 | All nine declared capability sets match fixtures; no raw-map sink, old public event wrapper, or duplicate event construction path remains. |
| C13 | Core-only and optional-AI graphs resolve/compile/test one compatible v3 runtime set. |
| C14 | Package file lists, dependency constraints, examples, and the PR/evidence index are complete and consistent. |

Use fixed provider fixtures and `--seed 0`. Synchronize processes with calls,
messages, monitors, and barriers, not sleeps. Test delivery order through explicit
acknowledgement where needed. Compare normalized values and state/callback counts;
do not depend on generated UUID literals, current time, network latency, or live
credentials. Property tests supplement these cases; they do not replace gates.

## Verification commands and evidence

From each changed package, run at minimum:

```text
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test --seed 0 --exclude live --warnings-as-errors
mix quality
mix deps.unlock --check-unused
mix hex.audit
mix hex.build
```

Follow the package AGENTS.md for additional required commands and coverage.
Messaging's instructions require at least 90 percent coverage even if its current
mix.exs threshold is zero. Mattermost requires 90 percent; WhatsApp's current
configured floor is 80 percent. Record the applicable rule in the version matrix;
never lower a threshold or mark a failed mandatory check as passed.

Messaging's default test alias excludes integration/story/flaky tests. Run relevant
migration tests explicitly and the applicable inclusive suite. Run the existing
optional AI test through its declared alias against the pinned v3 AI source.

The new core integration subproject must implement these planned commands:

```text
cd jido_chat/integration
mix deps.get
mix test --seed 0 --exclude live --warnings-as-errors
MIX_ENV=test mix run scripts/verify_signal_migration.exs --phase all --manifest ../docs/migration/version-matrix.json
```

The gate script is one small verification entry point, not a new workflow engine.
It loads checked manifests, runs/asserts the required conformance matrix, and exits
nonzero if a required row is missing or fails. Implement it in G1; no claim is made
that it exists now.

Each gate record contains gate ID, pending/pass/fail state, exact source tree and
ref set, command, environment, exit status, result counts, evidence path/hash,
and any external blocker. Keep generated command logs bounded and free of raw
payloads or secrets. Store durable evidence with the core PR. A changed source
or dependency ref invalidates affected gate evidence; rerun those checks before
completion. Do not repeat unrelated tests merely to fill time.

## Resume, failure, and stop rules

Do not post progress comments to the GitHub tracking issue. The user stopped
those updates. Do not change the issue body to report progress. Keep progress
records in local files, commits, and this chat.

Make small progress commits after each complete change passes its relevant tests.
First, commit completed and tested work already in the worktrees. Do not wait for
all gates to pass. Keep each commit focused. Record passed checks and open work.
Keep all final completion requirements unchanged.

At each goal turn, read this plan and the latest gate status. Reuse existing
branches/checkouts and valid evidence; do not restart completed units. Work on the
first unpassed gate whose prerequisites pass. Preparatory independent work is
allowed, but never pass a dependent gate against missing upstream behavior.

On failure, record the exact failed command/assertion. Fix the relevant code and
rerun the focused test, then the affected required gate. Do not remove assertions,
relax schemas, silently mark support unsupported, or change the selected major to
make a gate pass. Report an external prerequisite with its source and current
state. Goal-tool blocked/paused status follows the host's rules; this plan does
not authorize bypassing them or marking incomplete work complete.

Stop the affected path if canonical data leaks private resources, a Bus request
executes a provider operation, membership evidence changes authorization/presence,
there is duplicate authoritative processing, or the proposed solution needs a new
inbox/outbox design. Record the failure and propose a separate change.

Merges, package publication, production activation, credentialed live tests, and
issue closure are separate actions. Prepare their concrete artifacts, but do not
perform them under the default implementation goal.

## Final review focus

No product-scope question remains. Review these concrete commitments before
starting the goal: the v3 prerequisite, the major public API change, room-level
source/subject rules, optional-AI compatibility, all nine adapters, and the G9
completion boundary. The upstream syntax and source commit are now verified.
The consumer dependency matrix remains G0 work, not an invitation to recreate
library features. Read the current gate status and B0–B2 checkpoint report before future work.
G0–G3 pass. G4–G9 remain pending. The user requested a stop at B2.


## B3 checkpoint result — October 13

G0–G5 pass. Membership and the Telegram/Slack pair meet their own acceptance
conditions. The B3 report maps each condition to current assertions and evidence.
Execution stopped at B3, as the user requested. G6–G9 remain pending.
See [CHECKPOINT_B3.md](../migration/CHECKPOINT_B3.md).
