# Jido Chat and Jido Assembly V3 Goal Brief

Status: approved; implementation active.

## Outcome

Jido Chat V3 owns the chat SDK, Jido Agent integration, optional managed
runtime, durable room behavior, and provider bridge behavior that Jido
Assembly needs. Jido Assembly V3 runs on consolidated Jido V3 and Jido Chat V3,
has an updated usable UI, and has no runtime dependency on `jido_messaging`.

The result gives Jido one chat stack for applications, Agents, rooms, storage,
and provider interaction.

## Consumer

The immediate consumer is Jido Assembly as the local integration showcase for
Jido Chat V3. Jido Chat hosts and provider adapter packages are also consumers
of the final public contracts.

## Included Work

- Move the Jido Assembly behavior that still depends on `jido_messaging` into
  supported Jido Chat V3 contracts or Assembly-owned product code.
- Complete the missing Jido Chat runtime features needed for durable provider
  bindings, bridge provisioning, messages, threads, reactions, queries,
  realtime notifications, and presence integration.
- Keep storage framework-neutral. The Jido Chat contract must permit direct
  adapters for Ecto, Ash resources, or another host storage system.
- Migrate every Jido Chat provider adapter in this workspace to the V3 contract
  and run its applicable tests.
- Migrate Jido Assembly to consolidated Jido V3 and Jido Chat V3.
- Replace old Jido Messaging module calls, records, signals, supervisors, and
  tests in Jido Assembly.
- Update Jido Assembly documentation, inspector content, and UI for the V3
  architecture.
- Start Jido Assembly, test its main flows in a browser, and correct defects.
- Retire `jido_messaging` after the replacement and migration evidence is
  complete. Do not keep a compatibility shim or a maintained reference
  implementation.

## Excluded Work

- Full Slack feature parity.
- Feature-for-feature preservation of the complete Jido Messaging API.
- Jido Messaging delegation, onboarding, trust-evidence, credential, grant,
  agent-directory, and Jidoka-specific records unless a selected V3 consumer
  proves that Jido Chat must own the behavior.
- Production login, enterprise authorization, billing, compliance, or SSO.
- A new identity package or storage package.
- Provider credential creation or secret ownership in Jido Chat.
- Remote publishing, release tags, pushes, or repository archival without
  separate authority.
- Preservation of existing Assembly V1 demo data unless the owner selects it.

## Delivery Rule

Each delivery unit uses the same closed loop:

1. Inspect current code and write a bounded implementation plan.
2. Implement the complete unit and its tests and documentation.
3. Run focused checks and the applicable package quality gate.
4. Run an Elixir design review against the resulting code.
5. Fix all supported findings and repeat the checks.
6. Create a local checkpoint commit only when the owner requests or authorizes
   it.
7. Recheck the remaining gap before starting the next unit.

The next unit cannot hide an unresolved finding from the prior unit.

## Repository Preflight

This snapshot uses the local remote-tracking refs observed on 2026-11-16. Each
repository must be checked again immediately before its delivery unit. Do not
reset, rebase, switch, or overwrite a branch to make the workspace uniform.

| Repository | Current branch and commit | Constraint before work |
| --- | --- | --- |
| Jido Chat | `release/v3` at `810ef0c`, five commits ahead | Preserve all five local commits. The draft goal brief is the only untracked file. |
| Consolidated Jido | checkout `main` at `0e91200`; `release/v3` at `ec96da60` | Use the reviewed V3 ref without changing the shared checkout unexpectedly. |
| Jido Messaging | `main` at `9a31231` | Clean source repository; its retirement notice is incomplete. Use it only as temporary behavior evidence. |
| Jido Showcase and Assembly | `main` at `141124e`, one commit behind | Inspect and integrate the incoming Hologram dependency change before the Assembly migration. |
| Discord, Mattermost, Signal, Telegram, WhatsApp | clean `main` branches | Recheck remote refs before each adapter unit. Mattermost uses the `www-zaq-ai` origin and needs separate remote authority. |
| GitHub and X | clean `main`, one commit behind | Inspect and integrate incoming documentation commits before migration. |
| Slack | clean `main`, two commits behind | Inspect and integrate the incoming dependency and security updates before migration. |
| Teams | `feat/lifecycle-events` at `4124103`, one commit ahead of `origin/pr-14` | Preserve the unpushed timing-race fix and the feature branch history. |

All implementation and checkpoint commits remain local unless the owner gives
separate push authority. A unit must record the starting and ending commit for
each repository that it changes.

## Proposed Delivery Units

### Unit 0: Consolidated Jido V3 baseline

Result: Jido Chat uses the reviewed consolidated Jido V3 source and Joi schema
boundary. The exact source is selected for Assembly's later atomic V3 cutover.

Current baseline: consolidated Jido `release/v3` reports version
`3.0.0-beta.2`, contains `Jido.AI`, and is at `ec96da60`. Jido Chat pins commit
`047bf746`, which is five commits behind that head. The added commits include
the scheduling consolidation, durable definition recovery, retained durable
turn results, and a V3 recovery gate. `ec96da60` is the proposed Unit 0 source
candidate, subject to the full Jido Chat checks and design review. Assembly
depends on `jido_ai ~> 2.2` and uses its V2 Agent options, `ask_sync` helper,
model alias configuration, and transitive `ReqLLM` API. Jido Chat also declares
`zoi` directly and uses `Zoi.*` in 78 production files. The consolidated V3
schema facade is `Jido.Joi`.

Done when: one reviewed Jido V3 commit is selected and used by Jido Chat, and
Jido Chat passes its V3 checks and design review on that commit. Assembly uses
the same commit during Unit 5, when `jido_messaging`, the V2 adapters, standalone
`jido_ai`, and their incompatible dependency graph leave together.

Observed sequencing constraint: consolidated Jido V3 requires Zoi 0.19, while
current `jido_messaging` and its V2 `jido_chat` dependency require Zoi 0.18.
Dependency resolution rejects the combined graph. The project will not use an
override compatibility shim.

Unit 0 migration slices:

1. **0A - Consolidated source gate.** Test Jido Chat against `ec96da60`, inspect
   the five intervening Jido commits, update the pin only after the focused and
   full checks pass, and record the selected commit for Assembly and adapters.
2. **0B - Joi schema boundary.** Move Jido Chat Action, Signal, Agent, Runtime,
   and public value schemas to `Jido.Joi`. Refactor unsupported Zoi convenience
   calls without changing null, optional, numeric-range, default, or stored
   value semantics. Decide `unrecognized_keys: :error` or an open boundary for
   each external schema. Replace direct error inspection with the supported Joi
   error accessors where possible.
3. **0C - Dependency and configuration hygiene.** Remove the direct `zoi`
   dependency only after production and test source no longer calls it. Keep
   Spark and Splode direct because Jido Chat uses their public modules. Confirm
   that no split Jido package or old application configuration remains.
4. **0D - Baseline verification.** Run formatting, warnings-as-errors compile,
   the full test suite, Covenant contracts, quality, documentation, coverage,
   and the unused-dependency check. Run the Elixir design review, fix every
   supported finding, and repeat the affected checks.

Required schema evidence includes rejected undeclared Signal fields, preserved
portable JSON round trips, unchanged default and nullable behavior, stored
Agent and Runtime value validation, and no direct `Zoi.*` call in Jido Chat or
Assembly source.

### Unit 1: Durable provider declarations and bridge provisioning

Status: complete in the local working tree on 2026-11-16. The package has 455
passing tests, 25 of 25 contract obligations, 90.1% coverage, and passing
quality, documentation, dependency, compile-graph, and design-review gates.

Result: A host can declare provider definitions in trusted code, store
credential-free connection and mapping records, provision them through the
runtime, and recover the managed Agent process tree.

Depends on: Unit 0 and the current durable room runtime.

Done when: declarations, mappings, desired state, storage restart, activation,
failure recovery, and secret-reference boundaries have focused tests and pass
the Jido Chat quality gate and design review.

Proposed minimum contract:

- A static `connection_definitions` registry maps stored definition keys to
  trusted provider-account Agent modules. Stored data cannot name a module or
  create an atom.
- A durable connection declaration stores account ID, definition key, desired
  state, revision, opaque secret references, safe provider settings, and
  metadata. It never stores resolved credentials.
- A durable bridge binding stores account ID, local Room ID, external Room ID,
  direction, enabled state, revision, and metadata.
- New `Connections`, `Bindings`, and atomic `Commit` storage capabilities keep
  the same host-owned adapter shape as current Room storage.
- The managed Runtime merges startup and durable connection declarations,
  resolves trusted definitions, overlays active stored bindings, and starts or
  stops the provider Agent only through the host Jido instance.
- A small host-supplied secret resolver maps opaque references to
  operation-scoped credentials at activation. Jido Chat owns no secret store
  and logs no resolved value.
- Provision and deprovision APIs persist desired state before reconciliation.
  Deprovisioning stops the Agent and preserves Room history and provider work
  evidence.
- The first routing contract is explicit binding direction plus deterministic
  broadcast to all active outbound bindings. Do not copy the old general
  routing-policy system until a selected V3 consumer requires it.

Required failure evidence includes unknown definition keys, missing storage
capabilities, missing secret resolvers, secret resolution failures, duplicate
external bindings, revision conflicts, activation failures, restart recovery,
and one failed declaration not blocking another.

### Unit 2: Assembly chat data and queries

Status: complete in the local working tree on 2026-11-16. The package has 468
passing tests, 25 of 25 contract obligations, 90.4% coverage, and passing
quality, documentation, dependency, compile-graph, and design-review gates.

Result: Jido Chat supplies durable message and reaction facts and queries that
Assembly can project. Assembly owns user profiles, search presentation, and
Hologram view models.

Depends on: selected Assembly persistence target.

Done when: posting, thread derivation, reaction transitions, query cursors,
restart, idempotency, and authorization tests cover the selected contracts and
pass the Jido Chat quality gate and design review.

Current ownership boundary:

| Assembly need | V3 owner | Current state |
| --- | --- | --- |
| Managed Room and provider Agent process tree | Jido Chat | Present |
| Durable Room records, membership, and message history | Jido Chat | Present |
| Message posting and thread identifiers | Jido Chat | Present; Assembly can derive threads from history |
| Durable reactions | Jido Chat | Present with revisioned current state, tombstones, bounded queries, and Room facts |
| User and Agent display profiles | Assembly or host identity system | Keep out of Jido Chat storage |
| Search result shaping | Assembly | Keep over the selected host storage and projection |
| Presence sessions | Assembly through Phoenix Presence | Keep Phoenix out of Jido Chat |
| Realtime committed facts | Jido Signal Bus through Jido Chat Rooms | Present; replace Jido Messaging PubSub use |
| Provider declarations, bindings, policy, and recovery | Jido Chat | Present for explicit direction, deterministic broadcast, desired state, and restart recovery |
| SQLite implementation | Assembly | Implement Jido Chat storage capabilities locally |
| Command results | Consolidated Jido turn and Signal contracts | Do not copy `Jido.Messaging.CommandResult` |

Proposed minimum reaction and thread contract:

- Keep message history immutable. Do not add reactions, receipts, or delivery
  status as mutable fields on `Jido.Chat.Message`.
- Treat a thread as messages that name one `thread_id`. Derive roots, replies,
  and reply counts from history. Do not copy the old separate Thread record for
  Assembly.
- Add authorized Room commands to add or remove the caller's reaction from one
  retained message. The caller must be an active member and the message must
  exist in that Room.
- Reuse the canonical `jido.chat.reaction.added` and
  `jido.chat.reaction.removed` facts for committed local changes. Publish them
  on the Room Signal Bus only after storage accepts the transition.
- Add one small `Reactions` storage capability. Its identity is Room, message,
  reaction, and actor. Add is idempotent; remove is idempotent; queries return
  deterministic current reaction state for one message or bounded message set.
- Hydration does not copy every reaction into Agent state. Assembly reads the
  projection through the Runtime facade.
- Keep message edit, delete, receipts, global search, and separate thread
  lifecycle records outside this unit. Add them later only for a selected V3
  consumer.

Required evidence includes duplicate add, repeated remove, missing message,
wrong Room, nonmember, restart recovery, bounded queries, concurrent revision
or uniqueness behavior, storage failure before Agent commit, and Room Bus
publication after commit.

### Unit 3: Realtime activity and presence boundary

Status: complete in the local working tree on 2026-11-16. The Runtime now owns
one bounded application-wide Signal Bus, durable Rooms publish exact committed
message and reaction facts to it, and presence remains host-owned. The package
has 473 passing tests, 25 of 25 contract obligations, 90.3% coverage, and
passing quality, documentation, dependency, compile-graph, and design-review
gates.

Result: Assembly can subscribe to committed Jido Signals and can plug Phoenix
Presence or another host presence system into Jido Chat without a Phoenix
dependency in core.

Depends on: Unit 2 signal and record contracts.

Done when: committed writes notify subscribers, presence remains host-owned,
two clients converge on stored state, and tests pass the Jido Chat quality gate
and design review.

Proposed minimum realtime contract:

- The optional managed Runtime starts one bounded `Jido.Signal.Bus` before its
  manager. Starting the `:jido_chat` application still starts no process.
- Each Room keeps its existing isolated Bus for Agent participants. A durable
  Room also publishes committed message and reaction facts to the Runtime Bus.
  This gives host applications one observation point for dynamic Rooms without
  a second messaging process tree.
- The Runtime facade exposes subscribe and unsubscribe helpers for Signal type
  paths. It does not add a new PubSub protocol or wrap Signals in another event
  type.
- Storage stays authoritative. Runtime Bus delivery is a notification to
  reread durable state. A Bus or UI delivery failure cannot undo a committed
  message or reaction.
- Assembly replaces `Jido.Messaging` Signal subscriptions with one Runtime Bus
  subscription and uses Hologram realtime only at its UI boundary.
- Assembly keeps Phoenix Presence, heartbeat, TTL, and session tracking in the
  application. Jido Chat has no Phoenix dependency and owns no online-user
  table.
- Presence changes can update Assembly directly. They do not need durable Chat
  records or synthetic Room membership changes.

Required evidence includes dynamic Room creation, messages and reactions from
more than one Room, subscriber exit cleanup, Runtime restart and subscriber
reattachment, committed storage with failed notification, no notification for
a rejected command, and two Assembly browser clients rereading the same stored
state.

### Unit 4: Provider adapter V3 migration

Status: complete locally on 2026-11-17. Telegram, Discord, GitHub, Signal, X,
Slack, Teams, and WhatsApp use the Jido Chat V3 contracts. Telegram has 172 passing offline
tests, 38 excluded live tests, 18 of 18 contract obligations, and 93.0%
coverage. Discord has 67 passing offline tests, 12 excluded live tests, 20 of
20 contract obligations, and 93.5% coverage. GitHub has 15 passing offline
tests, one excluded live test, 10 passing Adapter Test Kit contract tests, and
96.13% coverage. Signal has 32 passing offline tests, one excluded live test,
12 passing Adapter Test Kit and Source contract tests, and 94.07% coverage.
X has 15 passing offline tests, two excluded live tests, 12 passing Adapter
Test Kit tests, and 96.05% coverage. Slack has 28 passing offline tests, one
excluded live test, 9 passing Adapter Test Kit and Source contract tests, and
60.9% measured coverage. Teams has 43 passing offline tests, one excluded live
test, 11 passing Adapter Test Kit contract tests, and 75.3% measured coverage.
WhatsApp has 165 passing offline tests, including 11 property tests, 3 excluded
live tests, and 80.9% measured coverage. Its Adapter Test Kit, push Source,
pairing, storage, runtime-recovery, identity, and media-reference tests pass.
The production compile, strict Credo, Dialyzer, Doctor, documentation,
dependency, compile-graph, and design-review gates pass for Slack, Teams, and
WhatsApp. All eight use the current sibling Jido Chat V3 source and
pass quality, documentation, dependency, compile-graph, and design-review
gates. No live provider call ran.

Result: Discord, GitHub, Signal, Slack, Teams, Telegram, WhatsApp, and X use
the Jido Chat V3 adapter and Signal contracts. Mattermost is not part of this
project and was removed from scope by the owner on 2026-11-16.

Depends on: stable core provider and bridge contracts from Units 1 through 3.

Done when: each adapter compiles and its applicable unit, contract, and adapter
test-kit checks pass. Live credential checks are reported separately from
offline contract checks.

Final local state:

| Adapter | Package version | Jido Chat source | Unit status |
| --- | --- | --- | --- |
| Discord | 1.1.0 | sibling V3 | complete |
| GitHub | 1.0.0 | sibling V3 | complete |
| Mattermost | 1.0.0 | unchanged | excluded by owner |
| Signal | 1.0.0 | sibling V3 | complete |
| Slack | 1.1.0 | sibling V3 | complete |
| Teams | 0.1.0 | sibling V3 | complete; feature branch preserved |
| Telegram | 1.2.1 | sibling V3 | complete |
| WhatsApp | 0.1.0 | sibling V3 | complete |
| X | 1.0.1 | sibling V3 | complete |

Each adapter is one closed delivery unit inside Unit 4. For each repository:

- Select the reviewed local Jido Chat V3 source during migration. Do not make
  tests depend on an unpublished Hex release.
- Use `channel_type/0`, a strict
  `:native | :unsupported` capability map, `invoke/3`, and `normalize/3`.
- Keep provider wire values and credentials behind the transport boundary.
- Use `operations/0` and `event_definitions/0` only for real provider
  extensions. Do not add provider branches to Jido Chat core.
- Use `Jido.Chat.Sensor.Source` for owned poll or push input. A host-owned
  webhook can call `Jido.Chat.normalize/2` directly.
- Add the shared Adapter Test Kit, native-operation fixture tests, stable
  normalization identity tests, and tests proving unsupported operations make
  no provider call.
- Run the repository test suite, quality alias, documentation build, and unused
  dependency check. A normal test run must make no live provider request.
- Run an Elixir design review, fix all supported findings, and repeat the
  checks before moving to the next adapter.

Live checks are separate evidence. Record the exact environment and provider
used, or state that only offline contract evidence is available.

### Unit 5: Jido Assembly V3 backend migration

Result: Assembly uses consolidated Jido V3 and Jido Chat V3 for its process
tree, durable chat behavior, Signals, Agents, and bridges. No production or
test source references `Jido.Messaging`.

Depends on: Units 0 through 4 and the selected persistence and data-migration
decisions.

Done when: dependencies and source references prove removal of
`jido_messaging`; seeded rooms, DMs, messages, threads, reactions, mentions,
search, presence, agents, and optional bridges pass Assembly tests and survive
the selected restart test.

Current baseline:

- The Assembly supervision tree starts Phoenix PubSub, `Jido.Assembly.Jido`,
  Phoenix Presence, `Jido.Assembly.Messaging`, seeds, a Messaging Signal
  notifier, the Messaging presence adapter, and the endpoint.
- `Chat`, `Chat.Projections`, `Chat.Mentions`, `Agents`, `Bridges`, `Seeds`,
  `Presence`, and `MessagingNotifier` call Jido Messaging directly.
- Assembly uses Jido Messaging SQLite records for rooms, participants,
  messages, reactions, threads, bridge configuration, room bindings, routing
  policy, presence Signals, and subscriptions.
- Assembly uses the old generated Jido instance API, `ask_sync`, standalone
  `jido_ai` configuration, and an undeclared transitive `ReqLLM` API.

Target dependency and process boundary:

- Select the same reviewed consolidated Jido V3 source for Jido Chat and
  Assembly. During local migration, use explicit local package paths. Do not
  depend on an unpublished Hex version.
- Add Jido Chat V3 and the reviewed V3 Telegram and Discord adapters. Remove
  `jido_messaging` and standalone `jido_ai`. Declare `exqlite` directly because
  the Assembly-owned storage adapter uses it.
- Keep `Jido.Assembly.Jido` as a supervised `use Jido` instance with a stable
  namespace. Use `Jido.start_agent/3`, `Jido.call/3`, and
  `Jido.AgentServer.call/3` with the instance. Do not use generated instance
  facade functions.
- Start dependencies in this order: Phoenix PubSub and Phoenix Presence,
  `Jido.Assembly.Jido`, the Assembly SQLite chat resource, the Assembly Chat
  Runtime, deterministic seed provisioning, the Runtime Signal notifier, the
  Assembly-owned presence service, and the endpoint. Telemetry and cluster
  children keep their normal application positions.
- Starting the `:jido_chat` application remains process-free. Assembly starts
  the optional managed Chat Runtime explicitly.

Target Assembly modules and ownership:

- `Jido.Assembly.ChatStorage` implements only the Jido Chat storage
  capabilities used by Assembly: rooms, declarations, memberships, immutable
  messages, reactions, connections, bindings, and atomic commits. SQLite
  tables and migrations stay in Assembly.
- `Jido.Assembly.ChatRuntime` uses `Jido.Chat.Runtime` with
  `Jido.Assembly.Jido`, the Assembly storage resource, trusted Room definition
  keys, trusted provider definition keys, and a host secret resolver.
- Assembly keeps display profiles, mention handles, search presentation,
  workspace metadata, Phoenix Presence sessions, Hologram view models, and UI
  notifications. It does not put these product concerns in Jido Chat.
- Remove `Jido.Assembly.Messaging`. Replace it with direct calls to the Chat
  Runtime facade and normal Jido turn contracts. Do not add an Assembly
  compatibility module that preserves the old Jido Messaging API.

Approved SQLite shape:

- Keep the adapter in Assembly and declare `exqlite` as a direct Assembly
  dependency. Jido Chat core keeps no SQLite, Ecto, Ash, or Repo dependency.
- Start one Assembly-owned storage resource before the Chat Runtime. It owns
  the SQLite connection, applies versioned Assembly migrations, and exposes a
  stable resource value to the Jido Chat adapter callbacks.
- Implement the seven current capability contracts: links, outbox, rooms,
  Room declarations, memberships, immutable history, and atomic commit. Add
  the connection, binding, and reaction capabilities delivered by Units 1 and
  2. Do not implement retired Jido Messaging specialty records.
- Use dedicated tables and indexes for each durable capability. Store portable
  JSON or Jido codecs, not opaque Erlang terms. Use exact revision predicates,
  deterministic cursor indexes, and unique keys for Room history sequence,
  message identity, memberships, external bindings, and reactions.
- Implement `Commit` with one SQLite transaction. A failed command rolls back
  the complete batch. Do not publish a committed Runtime notification until
  the transaction succeeds.
- Use a new Assembly V3 database path. Do not point V3 writers at the current
  Jido Messaging table, which mixes many record kinds in one table and stores
  opaque term payloads.
- Prove the framework-neutral boundary with core capability contract tests and
  the external Assembly SQLite implementation. Ecto and Ash implementations
  remain possible host adapters, but they are not dependencies or required
  implementations in this goal.

Approved clean-seed contract:

- Use a new V3 database path and never open the old Jido Messaging database
  from V3 code. The old ignored file is not deleted automatically. The user can
  remove it after the V3 cutover is verified.
- Give every seeded workspace, Room, profile, membership, provider
  declaration, and binding a stable source key. Track one Assembly seed version
  in the V3 database.
- On an empty database, provision Rooms and memberships through public Runtime
  APIs. Post the initial messages through normal Room commands, capture the
  returned message IDs for thread replies and reactions, and mark the seed
  complete only after all required records succeed.
- Seed provider-shaped demo messages before live provider declarations are
  enabled. Seed writes must not make an outbound provider request.
- On a second boot, do not duplicate or rewrite seed data. A retry after a
  partial failure uses stable source keys and completes only the missing work.
- Never delete or overwrite a user-created Room, message, membership, reaction,
  or connector declaration during startup. A later seed version can add new
  demo records, but it cannot reset user state.
- Tests cover an empty boot, a second idempotent boot, partial-seed recovery,
  preserved user data, stable thread and reaction relationships, and zero
  provider calls during seeding.

Migration slices inside Unit 5:

1. **5A - Dependencies and consolidated Jido AI.** Move configuration from
   `:jido_ai` to `:jido`, add a stable namespace, convert the three Assembly
   Agents to the consolidated graph-first AI DSL, and replace `ask_sync` and
   generated instance calls with normal Jido Signal and turn calls. Provider
   tests use a scripted inference client and need no live key.
2. **5B - Assembly SQLite capability adapter.** Add the direct `exqlite`
   dependency, schema, migrations, transactions, capability implementation,
   query bounds, revision checks, and restart tests. V1 and V3 writers never
   share one database. A clean V3 database is the proposed start state.
3. **5C - Runtime and chat context cutover.** Define Room and Runtime modules,
   update the supervision tree, and move room creation, memberships, posting,
   history, thread derivation, reactions, mentions, and search projections to
   Jido Chat V3. Parse `Jido.AgentServer.TurnResult` and committed Signals. Do
   not copy `Jido.Messaging.CommandResult`.
4. **5D - Realtime and presence cutover.** Subscribe one notifier to the
   Runtime Bus and reread durable state before Hologram broadcasts. Rebuild the
   small TTL and session service around Phoenix Presence in Assembly. Presence
   updates remain product events and do not become durable chat membership
   changes.
5. **5E - Provider bridge cutover.** Replace bridge configs, routing policies,
   bridge supervisor calls, and room bindings with durable Chat connection
   declarations and bindings. The host secret resolver reads environment
   references at activation. Missing credentials select deterministic demo
   mode. Active outbound bindings use explicit direction and deterministic
   broadcast.
6. **5F - Seeds, tests, and removal.** Provision deterministic rooms, DMs,
   memberships, messages, reactions, provider declarations, and bindings
   through public V3 APIs. Rewrite the Assembly tests against those contracts,
   remove old modules and fixtures, and scan production and test source for
   old dependencies and namespaces.

Each slice is a closed delivery unit. It receives its own plan, focused checks,
Elixir design review, supported-finding fixes, repeated checks, and gap check
before the next slice starts.

Required backend evidence:

- A dependency and source scan finds no `jido_messaging`, `Jido.Messaging`,
  standalone `jido_ai`, `config :jido_ai`, generated Jido instance runtime
  call, or undeclared `ReqLLM` call.
- A clean boot creates the expected workspace, channels, DMs, memberships,
  seeded history, threads, and reactions once. A second boot is idempotent.
- A Runtime and storage restart preserves committed rooms, memberships,
  messages, reactions, connection declarations, and bindings.
- Message, reply, and reaction commands return committed Jido turn evidence;
  rejected commands do not persist data or send a committed notification.
- Mentions resolve through Assembly-owned profiles. Search returns bounded
  Assembly view results over stored chat data.
- The notifier reconnects after Runtime restart, and two subscribers reread
  the same committed state.
- Presence heartbeat, expiry, leave, and multi-session behavior pass without a
  Jido Messaging macro or record.
- Telegram and Discord both work in credential-free demo mode. When selected
  credentials exist, durable declarations recover the provider Agents and
  bindings after restart.

### Unit 6: Jido Assembly V3 UI and browser QA

Result: The UI explains and exercises the V3 architecture and works as a chat
showcase on desktop and mobile.

Depends on: Unit 5.

Done when: the app starts on an available local port; browser QA covers room
navigation, send, reply, reaction, search, presence, two-tab realtime updates,
agent interaction, responsive layout, keyboard use, and visible error states;
all found defects are fixed and rechecked.

Current UI evidence:

- The page already supports channels, DMs, sending, threads, reactions,
  mentions, search, demo users, agent prompts, connector state, presence, and a
  developer inspector.
- The desktop rail and sidebar are hidden below the medium breakpoint. Mobile
  has a horizontal Room list, but it has no equivalent access to search, Room
  creation, demo users, or the full connector state.
- The developer inspector is hidden below the extra-large breakpoint. A mobile
  or tablet user cannot inspect the V3 stack and Signal path.
- Several formatting and attachment controls look active but have no action.
  They must not remain misleading controls in the V3 showcase.
- Hologram page tests cover state and server commands without a browser. The
  Assembly README correctly states that these tests do not prove layout,
  JavaScript behavior, SSE delivery, or cross-tab realtime behavior.

UI delivery slices:

1. **6A - V3 information and visual update.** Keep the current Room-first
   information architecture. Update the title, seed copy, connector state,
   stack path, contracts, Signal names, storage details, and inspector content
   to the final Jido V3 and Jido Chat V3 architecture. Remove all visible Jido
   Messaging claims. Keep connector demo mode clear and separate from a live
   provider connection.
2. **6B - Responsive navigation and inspector.** Add a usable small-screen
   route to channels, DMs, search, Room creation, demo-user selection,
   connector status, and the developer inspector. Preserve the desktop
   four-panel layout. The thread panel remains a drawer on small screens and a
   side panel on large screens.
3. **6C - Interaction and accessibility correction.** Keep only controls that
   perform a supported action, or make unsupported controls visibly disabled.
   Add clear pending, empty, failure, disconnected, and retry states. Check
   labels, focus order, focus return, dialog behavior, Enter submission,
   Escape close, keyboard-only use, readable contrast, and reduced viewport
   height.
4. **6D - Browser QA and repair.** Start Assembly on an available local port
   and test the final built assets in a real browser. Fix every in-scope defect
   and repeat the affected flow and the smoke suite.

Required browser evidence:

- Desktop at 1440 by 900, tablet at 1024 by 768, and mobile at 390 by 844 can
  open the workspace, navigate Rooms and DMs, and use the composer without
  hidden or clipped required controls.
- One client creates a Room, sends a message, adds and removes a reaction,
  opens a thread, sends a reply, searches for the message, and changes the demo
  user. The durable state remains after a page reload.
- Two independent browser clients show the same new message, reaction, and
  thread reply through Runtime notifications and durable rereads. Presence
  joins, heartbeats, multi-session state, and expiry are visible and correct.
- The developer inspector shows the actual V3 Room, Runtime, storage,
  connection, binding, turn, and Signal data. It does not show old Messaging
  modules or old Signal names.
- Credential-free connector demo mode works. Telegram and Discord live checks
  run only when selected credentials are present and are recorded separately.
- Agent interaction uses a deterministic scripted inference client for the
  required browser check. A live model check is optional and is reported as
  separate evidence.
- Browser console errors, failed network requests, layout overflow, stale
  pending state, duplicate events, and lost focus are treated as defects.
- Final screenshots record the desktop and mobile workspace and the developer
  inspector. Browser QA records the tested port, commit, viewport, and whether
  provider or model credentials were used.

### Unit 7: Jido Messaging retirement

Result: Jido Messaging is no longer an active implementation dependency and
the package and repository have no supported implementation or compatibility
role.

Depends on: Units 1 through 6.

Done when: all required behavior has proven V3 ownership, all consumers have
moved, the old package has a clear terminal state, no supported reference or
compatibility path remains, and the final cross-repository gap check is clean.

Current retirement evidence:

- Jido Messaging `main` is clean at commit `9a31231`, named `docs: retire jido
  messaging`.
- That commit added a retirement notice at the top of the README only. The
  same README still says that the package is being prepared for the 1.x
  release, tells users to install it, and presents its runtime and production
  storage guidance as current. This mixed state is not a complete retirement.
- The package manifest still describes and builds the active 1.1.1 package
  against split Jido V2 dependencies. Its implementation and detailed docs can
  supply temporary behavior evidence during the migration. They are not a V3
  target or a retained reference implementation.

Retirement slices:

1. **7A - Final behavior disposition matrix.** Compare public Jido Messaging
   modules, storage capabilities, Signals, supervisors, bridge behavior, and
   Assembly use against the delivered V3 stack. Mark each behavior as moved to
   Jido Chat, owned by the host, or retired. Any required behavior without
   delivered evidence reopens its owning earlier unit.
2. **7B - Local tombstone state.** Remove the active package implementation,
   tests, examples, generated documentation inputs, and current-use guidance
   from the final branch. Keep one short terminal README that states that the
   package is retired and names Jido Chat V3 as the replacement. Do not keep a
   compatibility shim, a reference package, or a maintained historical docs
   site. Git history remains repository history, not a supported product.
3. **7C - Ecosystem audit.** Search Jido Chat, all provider adapters, Assembly,
   and the relevant Jido documentation for active `jido_messaging` dependency,
   namespace, installation, and architecture claims. Correct in-scope stale
   guidance and produce the final gap report.
4. **7D - Remote retirement.** After explicit remote-action approval, retire
   the published Hex package as deprecated, archive the GitHub repository, and
   verify that the public package and repository surfaces state the terminal
   status. Do not publish a compatibility or reference release.

Required retirement evidence:

- The disposition matrix accounts for every behavior used by Assembly and the
  selected adapter/runtime scope. It does not claim that unported specialty
  APIs moved to Jido Chat.
- The final Jido Messaging branch is a tombstone, not a buildable compatibility
  or reference package. Its README points to Jido Chat V3 and makes no current
  installation, release, or support claim.
- No V3 package or Assembly source depends on `jido_messaging` or uses a
  `Jido.Messaging` runtime module.
- Jido Chat documents the replacement process tree, migration boundary,
  framework-neutral storage contract, identity plug-in boundary, and provider
  bridge model.
- A design review of the tombstone and ecosystem guidance finds no misleading
  current-use path or implied compatibility promise.
- With explicit remote authority, Hex shows the package as deprecated and the
  GitHub repository is archived. No new release is published.

## Goal Completion Evidence

- `jido_chat` is versioned for V3 and its full tests, quality gate, contract
  checks, documentation build, and storage migration tests pass.
- All provider adapter repositories pass the selected V3 compile and test
  matrix. Any check that needs live credentials is clearly identified.
- Jido Assembly has no `jido_messaging` dependency or `Jido.Messaging` source
  reference.
- Jido Assembly has no standalone `jido_ai` dependency or `config :jido_ai`;
  its Agents run through consolidated Jido V3.
- Jido Assembly passes formatting, warnings-as-errors compilation, tests,
  unused dependency checks, security audit, asset build, and Hologram compile.
- Browser evidence proves the listed desktop, mobile, and two-client flows.
- Each delivery unit has a completed design review and no unresolved supported
  finding.
- Documentation describes the final process tree, storage ownership, identity
  plug-in boundary, and provider bridge behavior.
- The final gap check finds no required Jido Messaging feature that Assembly or
  the stated Jido Chat V3 scope still needs.
- The published Jido Messaging package and repository have a terminal retired
  state and no maintained compatibility or reference implementation.

## Inputs and Dependencies

- Current `jido_chat` `release/v3` work and its V3 runtime plans.
- Current local `jido_messaging` source as temporary behavior evidence. It is
  not the target architecture and will not remain a supported reference.
- Current `jido_showcase/jido_assembly` application, tests, and roadmap.
- Consolidated Jido V3 public APIs and process ownership rules.
- User review after each material scope or product decision.

## Authority

Current authority permits local inspection, goal shaping, implementation after
the scope is clear, verification, design review, finding repair, and requested
local checkpoint commits. Remote writes, releases, and repository archival need
separate authority.

## Resolved Owner Decisions

1. **Complete Jido Messaging retirement.** Resolved by the owner on 2026-11-16.
   Port only behavior required by Jido Chat V3, its provider adapters, and Jido
   Assembly V3. Keep host and product concerns with their host. Retire the old
   package completely. Do not build backward compatibility and do not preserve
   a maintained reference implementation.
2. **Assembly-owned SQLite persistence.** Resolved by the owner on 2026-11-16.
   Assembly implements the Jido Chat storage capabilities with a new portable
   SQLite schema and a direct `exqlite` dependency. Jido Chat core keeps no
   SQLite, Ecto, Ash, or Repo dependency. The external adapter is part of the
   showcase proof that hosts can use their own storage framework.
3. **Clean Assembly V3 seed.** Resolved by the owner on 2026-11-16. Start
   Assembly V3 with a clean deterministic seed and do not migrate the old demo
   database.
   Assembly documents the database file as resettable demo state, and the V1
   serialized Jido Messaging records are not the V3 storage contract. The
   current ignored database is 64 KB and contains 9 rooms, 11 participants, 19
   messages, and one routing policy. Tests already use in-memory SQLite. A V1
   migration would require loading opaque term payloads through retired code
   for demo data that the documented reset path already replaces.
4. **Preserve and update the current UI structure.** Resolved by the owner on
   2026-11-16. Preserve the present Slack-like information architecture,
   update the visual system and V3 inspector, and correct usability defects
   found in browser QA. Do not add Slack parity.
5. **Offline provider verification with conditional live checks.** Resolved by
   the owner on 2026-11-16. Require offline compile, contract, and adapter
   test-kit checks for every adapter.
   Run live Telegram and Discord checks only when credentials are available,
   because Assembly exposes those two live connectors.

All material scope decisions are resolved. Unit 0 implementation planning is
the next action. Checkpoint commits, pushes, releases, Hex retirement, and
GitHub repository archival still require their named authority.
