# Public Signal migration

This migration is in progress. G0, G1, and G2 have passed. G3–G9 are pending.
The full package group is not ready for use.

The isolated native PostgreSQL fixture works. Current complete Messaging checks
pass 1,485 tests with zero skips and 85.3 percent coverage. Both current complete
runtime profiles pass all 1,485 checks.
The required 90 percent floor remains unmet.

The execution plan is
[2026-10-12-002-public-signal-boundary-plan.md](../plans/2026-10-12-002-public-signal-boundary-plan.md).
Issue [#65](https://github.com/agentjido/jido_chat/issues/65) tracks the work.
Issue [#64](https://github.com/agentjido/jido_chat/issues/64) records the feature request.

## Progress commits

Make a small progress commit after each complete change passes its relevant tests.
Do not wait for all gates to pass. Keep each commit focused. Put passed checks and
open work in its commit message and in `progress-commits.json`.
All final completion requirements stay the same.

The tested work is saved in focused progress commits. Both runtime harnesses
pass 241 checks. Four optional AI fixtures pass without a model call. Core proof
reuses 257 passing tests because its library, tests and pinned refs are unchanged.
Current Messaging quality, API audit and source scan pass.

Do not add GitHub issue progress comments or change the issue body for progress.
Record progress in this chat, local files and commit messages.

A cold adapter now uses its declared channel type when the gateway builds the
session key. The first send selects its stored route. Execution tests also check
invalid requests, missing provider targets, private failures and exact retry counts.

Directory and advisory records now have additional scope and cleanup proof.
Native thread store tests verify rejection before a write and accepted state
after a backfill failure. Test-only changes reuse checked production evidence
after an exact source comparison; complete test profiles are refreshed.

Projection failures return safe errors and keep canonical messages intact. A
failed later history page cannot start a partial rebuild. Credential rotation
checks preserve immutable proof identity and reject invalid lineage before
either record changes. The relevant changes and tests are committed.

History scope is validated before transcript queries and projection callbacks.
Real ETS and SQLite paging rejects foreign cursors and keeps complete rebuild
order. Durable membership, grant and invocation policy revisions preserve
immutable identity and terminal revocation in both stores.

Assignment save failures now return safely and restore the previous stored and
room assignment with one owned runner. Failed rollback reports both errors.
Missing topology binding IDs are rejected. Stopped Registry PIDs do not count
as active runners. The relevant tests pass, and each fix is committed.

Native runtime audit logs use the emitted Signal ID and direct parent ID. The
handler remains attached during message, receipt, reaction, presence, typing and
thread events. Direct native acceptance produces one received audit event after
the claim commits. Duplicate delivery and a failed Bus do not repeat this event.

Private media replacement now has separate stable upload and delete request IDs.
Repeated media requests reuse the prepared private resource. Complete bytes and
metadata remain private. Failed upload cannot delete the old message; failed
delete retains the replacement with a safe failure result.

Native multi-item retry retains each earlier accepted message and processes the
remaining items in order. Media policy denial writes no message; an exact-limit
retry keeps the complete media. YAML routing values now use fixed canonical
values. The typed broadcast test verifies two callbacks and no repeat on retry.

Native media now resolves all private references before canonical processing.
Invalid or unavailable resources cause no record writes. Complete media remains
in owned storage. Native replies retain the correct parent, thread and context
in each room. The relevant tests pass, and each change has its own commit.

Provider message lookup now includes the canonical room. Update, delete, and
reply tests use the same provider ID in two rooms. The Sender capacity test now
checks all 1,000 queue places and the rejected next job.

These checks use the combined worktrees. Final current-head PR CI, all-adapter
conformance, package checks, and the 90 percent Messaging coverage floor are
still required. G3 remains open. Inclusive coverage is 85.3 percent. The required
90 percent package coverage is not met.

Automatic thread creation now follows policy and the first message write. A
later link failure keeps the accepted message and produces a causal failure fact.
Repeated delivery does not repeat the provider callback. Message facts keep one
complete text field; a 140,000-byte message remains observable.

The other 13 provider fact types retain their external IDs and context. Messaging
observes them in order. They do not issue commands or infer canonical record
changes. Runtime reaction and receipt changes use typed authorized requests.

Typed room allocation keeps its bridge-scoped grant path. A room posting grant
cannot create an unrelated room. Creation cannot overwrite an existing room.
The low-level `create_room` function stores a Room record without a Signal.
The source scan now checks all 369 current core, Messaging, and Signal provider
library files and records exact source hashes. It has zero findings. Full
all-provider export and conformance checks remain required.

A maximum-size Chat message keeps its complete content in owned storage. Its
runtime fact uses canonical IDs and a closed result reference when needed.
Maximum-size local posts use the same private runtime resource owner for their
facts and results. The result is validated before the canonical write. Storage
failure cancels the prepared resources. Repeated execution does not repeat a write.

Use `resolve_resource` and `cancel_resource` on the instance for private resource
control. A reference belongs to its creator process. A different active caller
gets an ownership error. An expired or completed creator call cannot resolve the
value; lookup clears it. A call-scoped reference has no restart-safe replay claim.

Message acceptance checks the prepared record ID if a store call fails. A
confirmed saved message remains accepted. A confirmed absent message permits
retry. If the confirmation read fails, acceptance returns
`request_outcome_unknown` on each retry. It holds both private claims until an
explicit clear or runtime shutdown. Do not report that error as successful
acceptance. Existing transport acknowledgement order still applies. This state
has no restart-safe guarantee.

A runtime observation failure after a confirmed message write keeps the record
and the accepted claim. It emits a registered failure fact when the Bus is
available. Repeated delivery cannot repeat that message write.

The CreateRoom kind now matches the four stored Room types. Unknown kind fails at
the constructor. Current checks pass 1,485 complete Messaging checks. The unchanged core has
257 passing tests. Four optional AI tests pass. The Catalog has 110 native definitions.
Current coverage is 85.3 percent, below the required 90 percent.

Lifecycle delete failures keep safe errors and exact store counts. A stopped
runtime or deduper rejects acceptance before a store or provider call. Private
subscription records keep the caller's bridge and adapter scope. Malformed
pages cannot create records or change another bridge's records.

The demo CLI can start its local runtime without a provider token. Its startup
tests use fake adapters and no provider or model operation. CLI, dotenv, and
YAML settings retain their intended route IDs and environment precedence.

## Dependency baseline

The checked source graph uses these immutable refs:

| Package | Ref |
| --- | --- |
| Signal | `d6611eca1c95eb507843baceb55991e4801d8421` |
| Jido | `90763478104f1edbf0afcfcf9444621c3f9755e8` |
| Action | `8e9b3f7b268e175091b0eb3720bab3b8633d3c24` |
| Optional AI | `1f19ff262081bc13eb30da7bff8bfe42685d63c8` |
| Zoi | `2fff2a23e23e7ac0b26f62f49bbc1b12f7818ac9` |

The graph also pins Runic 0.1.0-alpha.11 and Decimal 3.2.0. The AI profile pins
ReqLLM 1.27.0 and LLM DB 2026.10.2. AI declares version 2.3.0 at its selected
v3 source ref. The source ref is the compatibility identifier.

The newer Action ref `d7358a32cde07429848278d98f994fbb121393ea` cannot replace
the selected Action ref in this graph. It removed APIs that Jido and AI still use.
The failed compile remains in `evidence/g0/`.

## G0 baseline commands

These commands record the G0 baseline. The current consumer sources still need
the G3–G6 changes before the complete integration run can pass.

The `integration/` project is for development and tests. It is excluded from the
core Hex package. Place the core and Messaging candidate checkouts in sibling
folders. Run these commands from the core `integration/` folder:

```text
MIX_ENV=test mix deps.get
MIX_ENV=test mix test --seed 0 --exclude live --warnings-as-errors
MIX_ENV=test mix test.chat --warnings-as-errors
MIX_ENV=test mix test.messaging --warnings-as-errors
MIX_ENV=test mix run scripts/report_dependency_graph.exs
```

For the optional AI profile, use a separate build folder:

```text
JIDO_INTEGRATION_AI=1 MIX_BUILD_PATH=_build/with_ai MIX_ENV=test mix deps.get
JIDO_INTEGRATION_AI=1 MIX_BUILD_PATH=_build/with_ai MIX_ENV=test mix test --seed 0 --exclude live --warnings-as-errors
JIDO_INTEGRATION_AI=1 MIX_BUILD_PATH=_build/with_ai MIX_ENV=test mix run scripts/report_dependency_graph.exs
```

The Messaging package can use `JIDO_CHAT_PATH=../jido_chat` in development and
tests. The production dependency source cannot use this path override.
Run `mix test.optional_jido_ai` from Messaging with the same path setting.
The optional test loads the Agent/Profile definition and checks its declared
model, tools, result, and limits. It makes no model or provider call.

G0 does not establish final coverage, package quality, or adapter conformance.
Those checks remain required in G7. Messaging's baseline has four pre-existing
skipped tests and excludes 43 tests through its default categories. No new test
uses a skip or live tag. The inclusive and applicable integration suites remain
required.

## Contract inventories

`api-map.json`, `catalog.json`, `operations.json`, `adapter-matrix.json`, and
`protocol.json` record the checked contract. The G1 verifier passed. The catalog
has 110 native definitions, the operation table has 26 rows, and the adapter
matrix has all nine source/transport rows. The API map classifies 3,486 source
and generated exports. The G1 check is:

```text
MIX_ENV=test mix run scripts/verify_signal_migration.exs --phase G1 --manifest ../docs/migration/version-matrix.json
```

The final `--phase all` command must also execute C01–C14. That runner is pending.
The current verifier reports this gap as a failure.

## G2 core boundary checks

Core has one typed executor for all 26 provider operations. It validates native
Signal metadata, schema, and conversation keys before a callback. It keeps an
admitted result or error in local memory. A result error cannot repeat the callback.
This memory does not survive process termination or a restart.

The old Chat object, event wrappers, result DTOs, and core queue/lock helpers are
removed. Thread and ChannelRef keep their value constructors and serialization.
They have no transport methods. `core-retired-modules.json` and
`core-test-migration-map.json` record the changes. `new-major-core-api.json`
records 1,219 compiled core and Signal-provider library exports.

Core tests pass (253 tests, seed 0). Core quality passes format, compile with
warnings as errors, Credo, Dialyzer, and Doctor. Signal provider tests pass (54
tests, seed 0; one existing live test is excluded). Its strict quality check
passes. The native catalog check builds and checks all 110 definitions through
JSON. This G2 check compiles Messaging definitions only. Full Messaging runtime
checks remain in G3 and G7. The source scan has no findings in 133 library files.

Run from core:

```text
MIX_ENV=test mix test --seed 0 --exclude live --warnings-as-errors
MIX_ENV=test mix quality
MIX_ENV=test mix run integration/scripts/verify_g2_catalog.exs
python3 integration/scripts/scan_public_boundary.py
```

Run from the sibling Signal provider checkout:

```text
JIDO_CHAT_PATH=../jido_chat MIX_ENV=test mix quality --seed 0 --warnings-as-errors
JIDO_CHAT_PATH=../jido_chat MIX_ENV=test mix run ../jido_chat/integration/scripts/export_g2_api.exs
```

Signal polling sends a checked delivery to its sink. It keeps all receive items
in order. It reports sink failure and uses polling backoff. The provider can
consume receive input before sink acceptance. No durable redelivery is claimed.
The mapper accepts both notification forms in the
[signal-cli JSON-RPC manual](https://github.com/AsamK/signal-cli/blob/master/man/signal-cli-jsonrpc.5.adoc).

## Consumer migration and release status

Chat owns the `Jido.Chat.Signal.*` definitions and `jido.chat.*` types. Messaging
owns the `Jido.Messaging.Signal.*` definitions and `jido.messaging.*` types.
The Signal provider keeps ownership of the `Jido.Chat.Signal` parent module.

The next major line will use configured bindings, typed requests and results,
ordered normalized deliveries, and direct Messaging acceptance. Old event
wrappers and tuple event mirrors will be removed. Domain records and input
builders have a separate classification in the API map.

The old 1.x release line remains available to existing consumers. The version
matrix records rollback source pins. The new major versions are not published.
PR review, package publication, and production activation are separate steps.
No package or PR is ready for release at this stage.
