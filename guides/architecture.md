# Jido Chat Messaging merge implementation plan

## Review status

This document adapts the completed Jido Messaging architecture to one
`jido_chat` package and one `:jido_chat` OTP application.

This plan is implemented on the `release/v3` branch. Runtime source is now in
this repository. Ecto work remains deferred.
The existing `jido_messaging` architecture is the source design. The new design
changes its package name, module names, data boundary, and bridge contract.

This is a clean cut:

- Do not add `Jido.Messaging` compatibility modules.
- Do not add aliases for old module names or old Signal types.
- Do not copy the old Messaging facade or its large persistence contract.
- Do not migrate old `jido_messaging` records or database schemas.
- Defer the optional Ecto adapter and its migrations until after the 3.0 merge.
- Do not include Hex release or package-retirement work in this build.
- Use the current small Messaging implementation as source material.

## Purpose

`jido_chat` supports three levels of use in one package:

1. Core is a stateless SDK for chat data, provider operations, rendering, and
   normalization.
2. Integration connects one Jido Agent activation to one or more provider
   Clients and input Sources.
3. Runtime supplies local rooms, participants, provider account lifetime,
   bridges, bounded provider work, and domain storage contracts.

A user can select only the level that is required. Package startup starts no
Chat process. A local room does not require a provider connection or database.

## Architecture decision

Use these boundaries:

| Boundary | Module namespace | Responsibility |
|---|---|---|
| Core | `Jido.Chat.*` | Stateless values, Signals, Actions, provider Clients, adapter contracts, rendering, normalization |
| Integration | `Jido.Chat.Plugin.*` and `Jido.Chat.Sensor.*` | Agent Plugin, provider Sources, Sensors, activation-local state, post-commit provider calls |
| Runtime | `Jido.Chat.Runtime.*` | Room policy, participant behavior, account activation, bridges, provider work, domain storage |

Core uses the root `Jido.Chat` namespace. Integration keeps the existing public
`Jido.Chat.Plugin` and `Jido.Chat.Sensor` names. Do not add a
`Jido.Chat.Integration` compatibility namespace. Runtime uses its own nested
namespace. Core must not call Integration or Runtime.

The permitted direction is:

```text
Runtime ────────> Integration
   └────────────> Core
Integration ───> Core
Core ──────────> no higher Chat boundary
```

Runtime can use Core directly. It does not need to pass Core values through an
Integration wrapper.

Jido remains the owner of Agent activation, control state, checkpoints, Plugin
resources, Router, Dispatch, and Signal Bus processes. Jido Agent persistence
does not replace Chat domain storage. Chat storage owns queryable room records,
message history, bridge links, and provider work records.

Provider packages remain separate packages. They implement Core adapter
contracts and Integration Source contracts.

## Boundary enforcement

Add the `boundary` package as a compile-time dependency. Define the package and
Runtime boundaries in the namespace roots:

```elixir
defmodule Jido.Chat do
  use Boundary,
    deps: [],
    exports: [
      Client,
      Adapter,
      Delivery,
      Message,
      Content,
      Markdown,
      Card,
      Modal,
      StreamChunk,
      Plugin,
      Sensor
    ]
end

defmodule Jido.Chat.Runtime do
  use Boundary,
    deps: [Jido.Chat],
    exports: [Room, Participant, Connection, Bridge, Storage]
end
```

The exact export list must match the final public API. Start with the smallest
list. Internal modules must not become exports only to make a compile error go
away. Because Integration keeps its existing public names in the Core namespace,
focused architecture tests enforce the Core-to-Integration rule that the
namespace boundary cannot express.

The Boundary compiler and focused architecture tests are required quality
checks. The build must fail for these dependencies:

- Core to Integration.
- Core to Runtime.
- Integration to Runtime.
- Provider adapter code to Runtime internals.
- Runtime code to an Integration internal module that is not exported.

Add focused architecture tests for rules that Boundary cannot express clearly.
In particular, Core must not start a process, create an ETS table, or own an OTP
supervision tree during application startup.

## Core boundary

Core owns portable chat meaning. It performs no durable storage and owns no
long-lived process.

Core responsibilities are:

- Immutable provider Client configuration.
- Provider adapter behavior and capability declarations.
- Typed command, query, completion, failure, and incoming fact Signals.
- Provider request execution through Jido Actions.
- Complete provider delivery normalization and validation.
- Portable actor, message, content, media, file, and resource-reference values.
- Markdown, card, modal, keyboard, emoji, and stream-chunk values.
- Serialization and revival of portable values.
- Conversion of normalized message history to AI model messages.
- Deterministic fallback rendering.
- Adapter conformance tests.

Core does not own:

- Rooms with live membership.
- Message history retention.
- Account activation.
- Provider polling or gateway processes.
- Durable deduplication.
- Work queues or automatic retries.
- Identity binding across providers.
- Bridge mappings.

### Canonical data contract

Restore a small stateless data model before Runtime bridge work starts.

Proposed public values are:

- `Jido.Chat.Actor`
- `Jido.Chat.Message`
- `Jido.Chat.Content`
- `Jido.Chat.Media`
- `Jido.Chat.FileSource`
- `Jido.Chat.ResourceRef`
- `Jido.Chat.Post`
- `Jido.Chat.AI`

`Jido.Chat.Post` is the canonical outbound request value. It supports text,
Markdown, a card, files, media, a stream source reference, and provider-safe
metadata. It is data, not a provider operation and not a stored room record.

`Jido.Chat.Message` is a normalized message snapshot. It supports actor, role,
content parts, room and thread references, reply context, provider identifiers,
and timestamps. It does not contain local runtime delivery state, grants,
receipts, retry records, or process references.

The command and event Signal schemas must use these value schemas or exact wire
forms derived from them. Do not maintain a separate rich value model and a
text-only Signal model.

### Vercel Chat SDK framing

Core retains the stateless parts of the earlier Vercel Chat SDK target:

- Postable content.
- Normalized messages and actors.
- Files and media.
- Markdown, cards, and modals.
- Structured streaming values.
- Capability and fallback rules.
- AI history conversion.

Runtime owns the process-related parts that were previously mixed into the
Vercel-style Chat facade:

- Subscriptions.
- Deduplication windows.
- Per-room state.
- Locks, queues, and concurrency policy.
- Handler and Agent lifetime.
- Provider connection lifetime.
- History and durable state.

Do not restore the old `Jido.Chat` state container, StateAdapter, handler lists,
or webhook event loop in Core.

## Integration boundary

Integration connects Core contracts to one Agent activation. It replaces the
current `Jido.Chat.Plugin` and `Jido.Chat.Sensor` namespaces.

Integration responsibilities are:

- Resolve immutable Clients when an Agent activates.
- Start an optional polling or push Sensor under that Agent activation.
- Admit only declared provider facts, rooms, and commands.
- Dispatch normalized incoming Signals to the Agent.
- Execute one admitted provider command after an Agent turn commits.
- Return the typed completion or failure Signal to the Agent.
- Keep a bounded activation-local duplicate window.
- Report local process status without claiming provider connectivity.

Integration does not own:

- Which account Agents exist.
- Account restart policy outside one activation.
- Durable cursors or duplicate records.
- Local rooms or room membership.
- Bridge mappings.
- Cross-account queues.
- Provider command retries.
- Canonical history.

Provider Sources own protocol acknowledgements, heartbeats, reconnect rules,
and provider transport details. They do not build Agent replies.

## Runtime boundary

Runtime adapts the small current Messaging design. It does not adapt the older
Messaging monolith.

Runtime responsibilities are:

- A small API over one required host-owned Jido instance.
- Local Room Agents and their Signal Buses.
- Participant Plugins and response policy.
- Provider account Agent definitions and activation through Jido.
- External-room to local-room bridge mappings.
- Provider and local message link records.
- Bounded post-commit provider work.
- Composable Chat storage capabilities.
- Recovery of pending work through Chat storage and Jido activation.

Runtime does not add another Agent lifecycle, router, Signal subscription
system, or provider adapter registry. It uses Jido and Integration.

## Application and process startup

Starting the `:jido_chat` OTP application starts no Chat process, ETS table,
Client registry, Sensor, room, queue, or storage resource.

The host defines a Runtime facade against an existing Jido instance:

```elixir
defmodule MyApp.Chat do
  use Jido.Chat.Runtime,
    jido: MyApp.Jido,
    storage: MyApp.ChatStorage
end
```

`MyApp.Chat` is configuration and a domain API. It is not another Agent runtime.
The host adds `MyApp.Jido` and any storage adapter resources to its supervision
tree. Jido Chat does not start a private Jido instance.

A Core-only user creates a Client and calls Actions without starting Runtime.
An Integration-only user activates an Agent with the Integration Plugin without
starting Runtime.

## Process tree

The target tree is:

```text
Host application
├── MyApp.Jido
│   ├── local room Agent
│   │   └── room Signal Bus
│   ├── participant Agent
│   └── provider account Agent
│       ├── Integration Plugin runtime
│       ├── optional Sensor
│       └── Runtime Bridge Plugin
└── host-owned storage resources, when required by the selected adapter
```

Jido owns account activation and lifetime. The Runtime facade delegates to
`Jido.activate_agent/4`, `Jido.start_agent_ref/4`, and related Jido functions.
Integration owns the Client and optional Sensor inside one account activation.

Each provider account has a stable Agent Ref. Two provider accounts use two
Agent activations. They are not interchangeable provider workers.

## Rooms and participants

`Jido.Chat.Runtime.Room` defines a Room Agent with a DSL and Plugin. The room
owns:

- Membership.
- A bounded working history or cache.
- A monotonic local sequence.
- One Signal Bus.
- Room admission policy.

An ephemeral room keeps its bounded history in Plugin state. A storage-backed
room treats Chat History as canonical and keeps only the bounded working data
that its decisions require. Jido persistence can checkpoint this working state,
but it is not the chat history database.

Participants compose `Jido.Chat.Runtime.Participant` into their Agent
definitions. They subscribe through managed Jido Bus resources. Their Actions
decide when to observe or reply.

Use full Jido Agent Refs for local member identity. The room must verify caller
authority for joins, leaves, reads, and posts.

A room-only use starts no provider account service or provider work process.
It can use ephemeral history or a selected History adapter.

### Runtime room message

The current Messaging room fact is text-only. Do not keep that limit in the new
design.

A Runtime room message contains:

- Local room Ref.
- Local sequence and stable message ID.
- Canonical local author identity.
- `Jido.Chat.Content` parts.
- Mentions.
- Reply and thread references.
- Origin metadata that is safe for local distribution.

It does not contain credentials, Clients, raw provider payloads, or process
references.

Room history stores the same content that the bridge publishes. A bridge must
not discard media, actor, mention, reply, or thread data before room admission.

## Provider accounts

`Jido.Chat.Runtime.Connection` composes the Integration Plugin into one account
Agent. The account definition selects its adapter, Client ID, credentials,
Source, allowed rooms, and commands.

The host starts an account through the Runtime facade:

```elixir
MyApp.Chat.start_connection("support", MyApp.SupportAccount)
```

The call delegates activation to the configured Jido instance and returns the
stable account Ref and AgentServer PID. Jido and the host own activation
lifetime. The Runtime facade does not add another owner process.

Credentials come from host-supplied values or secret references. They do not
enter Signals, room messages, stored work, logs, or status results.

Saved account configuration is not part of the first build. Add it later as a
separate Runtime contract if a host requires automatic account restoration.

## Bridges

`Jido.Chat.Runtime.Bridge` maps one account external room to one local Room Ref.
A mapping selects inbound, outbound, or both directions.

The account joins the local room as a service participant. The Bridge Plugin
translates:

- A normalized Core provider fact to a Runtime room post.
- A committed Runtime room fact to a Core provider command.
- A provider completion or failure to a Runtime work result.

The bridge must retain:

- Provider account ID.
- Provider room and message IDs.
- Local room and message IDs.
- Provider actor data and its local identity binding when known.
- Reply and thread links.
- Content parts that the target provider can accept.
- Origin data for echo prevention.

Provider input never creates a local room. The host creates rooms and approves
account membership before activation.

Provider messages sent by the account itself do not enter the local room again.
Local room facts that originated from the same account and provider message do
not go back to that provider.

### Capability loss

The bridge checks Core adapter capabilities before it submits outbound work.
It must use a documented fallback or return an explicit unsupported result.
It must not silently remove files, media, cards, or formatting.

## Provider work

Slow provider work runs outside Agent turns through a bounded worker owned by
the provider account's Bridge Plugin runtime. The worker claims only work for
that account from the Chat Outbox. It is not a generic Runtime queue.

The selected account and stable request ID remain fixed for the work lifetime.
The Integration Plugin marks work as `submitted` before it starts provider I/O.
Thus, a crash after that transition cannot cause an automatic duplicate call.

The state model is:

```text
pending -> claimed -> submitted -> completed
    ^         |          ├-------> failed
    └---------┘          └-------> unknown
```

A claim has a bounded lease. It can return to `pending` only before submission
starts. An unavailable account releases its unsubmitted claim. A known provider
failure is terminal. A timeout, lost worker, or indeterminate database result
after submission starts becomes `unknown`.

Runtime does not automatically submit `submitted`, `completed`, `failed`, or
`unknown` work again. Integration executes one admitted provider command and
does not add its own retry loop. A host can reconcile `submitted` or `unknown`
work through provider query support or an explicit operator policy.

## Storage and recovery

Chat storage is a first-class domain boundary. It is not an alias for Jido
Agent persistence.

The system has separate storage concerns:

1. Jido persistence stores Agent definitions, control state, Plugin state, and
   durable Turn progress.
2. Chat storage stores queryable room records, messages, threads, bridge links,
   and provider work.
3. A Signal Bus store keeps ordered delivery records and durable subscription
   cursors.
4. Provider packages own provider-specific cursors, acknowledgements, and
   protocol recovery state.

These stores can use the same database, but they have different contracts and
lifetimes. Do not force chat history into Agent checkpoints. Do not use the Bus
log as the Chat query model.

### Storage capabilities

Do not restore the old single persistence behavior with callbacks for every
Messaging subsystem. Define small capability behaviors. A storage adapter can
implement one or more capabilities:

- `Jido.Chat.Runtime.Storage.History` appends and reads ordered normalized
  message snapshots.
- `Jido.Chat.Runtime.Storage.Links` stores local-to-provider message links.
- `Jido.Chat.Runtime.Storage.Outbox` stores, claims, and transitions provider
  work.
- `Jido.Chat.Runtime.Storage.Rooms` stores room definitions and membership only
  when the host selects storage-backed rooms.
- `Jido.Chat.Runtime.Storage.Commit` atomically applies one batch across the
  capabilities of the same adapter when a workflow requires it.

The Runtime configuration selects the required capabilities explicitly. A
room-only application does not need Links or Outbox. An Integration-only
application does not need Chat storage.

An adapter reports its capabilities. Runtime validates the required set before
it starts a Room or account. A workflow that requires one atomic History and
Outbox write must use one adapter that implements Commit for both. Separate
adapters remain valid for workflows that define reconciliation between them.

Storage operations use immutable command and result values. They accept stable
request IDs and expected revisions where conflict detection is required. Calls
return typed values or typed errors. Adapters can use memory, ETS, an
event store, or a remote service without changing Room or Bridge decisions.

Keep adapter process ownership explicit. Jido Chat must not hide global tables,
repositories, or connection pools. The host supervises external adapter
resources. A test adapter can thread immutable state without a process.

### Deferred Ecto adapter

The optional Ecto adapter and its migration helper are not part of the
Messaging merge or the Jido Chat 3.0 acceptance gate. The merge supplies the
small storage capability contracts, their conformance suites, and a Memory
adapter. A later plan can add an optional Ecto SQL dependency, a host-owned Repo
contract, PostgreSQL and SQLite tests, and versioned migration helpers. Jido Chat
must not add an Ecto dependency or migration code during this merge.

### Commit boundaries

Chat storage, Jido Agent checkpoints, Signal Bus publication, and provider
effects do not share one transaction. This is an architectural fact, not an
adapter detail.

Every cross-boundary operation must therefore have:

- A stable request or event ID.
- Idempotent storage admission.
- An explicit state for an unknown provider outcome.
- A documented replay owner.
- Reconciliation after process restart.

Jido checkpoints do not replay post-commit Plugin effects. The Chat Outbox is
therefore valid domain storage when provider work must survive an Agent or VM
restart. It must stay a small capability, not grow into a generic job system.

This follows the Jido recoverable-effect protocol but changes the durable owner.
Jido normally permits a bounded pending intent in Agent or Plugin state. Chat
can have a large, queryable provider-work set, so the Chat Outbox is the
durable owner. Agent and Plugin state keeps only bounded coordination data such
as a cursor, active claim IDs, or health status. The account Plugin runtime
reconciles the Outbox during activation and restart.

This is a deliberate Jido v3 pressure point. Plugin startup, readiness, and
shutdown must support Outbox reconciliation without copying all pending work
into Agent state. If that lifecycle is difficult to express, improve the Jido
Plugin contract instead of adding a Chat supervisor.

Full recovery can require all of these parts:

- Configured Jido persistence for Agent control state.
- Chat History, Links, and Outbox adapters for selected Runtime features.
- A durable Signal Bus store when subscription replay is required.
- A host policy for account definitions and secret resolution.

The system does not claim exactly-once provider delivery.

## Jido v3 pressure test

Jido Chat is a demanding client of the Jido v3 architecture. It must use Jido
facilities directly when they match the required semantics. It must also report
friction instead of hiding it behind a second framework.

Use this ownership test:

- If a concern is about Agents, Turns, Plugins, Directives, Refs, topology,
  supervision, or Signal delivery, first solve it in Jido v3.
- If a concern is about rooms, messages, threads, provider links, chat history,
  or provider delivery intent, solve it in Jido Chat.

The first implementation must test these Jido v3 seams:

1. A Room Agent uses Jido Plugin state, admission, Directives, and Bus Plugins
   without a custom Agent lifecycle.
2. A provider account uses one Jido activation and one Integration Plugin
   runtime with secret-free persisted state.
3. Room publication uses the standard Jido Bus Manager and Client Plugins.
4. A storage append and later Signal publication remain idempotent across a
   crash between the two operations.
5. An outbound provider intent survives account restart without replaying a
   completed or unknown provider call.
6. Cross-Agent bridge work uses stable Agent Refs and Signals without a custom
   router or registry.
7. Burst input has bounded admission and visible backpressure. No hidden or
   unbounded queue is added in Chat.
8. Plugin quiesce, resume, and replacement work for provider configuration
   changes.
9. Many rooms and accounts remain isolated by Jido namespace and partition.

For each failed seam, record whether the missing capability belongs in Jido,
Jido Signal, or Jido Chat. Do not add a Chat-specific lifecycle, registry,
router, Bus, or generic task system to bypass a Jido limitation.

## Functional design rules

Keep the functional domain separate from process ownership:

- Core transformations accept values and return values or typed errors.
- Runtime decisions accept explicit state and commands, then return new state
  and data Directives.
- Plugins translate Directives into managed effects after a decision commits.
- Storage adapters translate immutable storage commands into external effects.
- Provider packages translate Core commands and facts to provider protocols.

Dependencies are explicit values. Public operations receive the selected Jido
instance and storage capabilities through the Runtime facade. Do not find them
through application-global registries or generated module names.

Macros can reduce authoring work, but they must produce ordinary Agent and
Plugin definitions. Business rules remain callable as normal pure functions.
Users can replace Room policy, participant response policy, storage
capabilities, provider Sources, and bridge policy independently.

Prefer composition of small behaviors over one behavior with optional
callbacks. A capability must not require an adapter to implement unrelated
room, history, bridge, or work functions. Supply conformance tests for each
capability.

## Signal names

Use only `jido.chat.*` Signal types. Do not keep `messaging.*` Signal names.

Proposed Runtime types include:

- `jido.chat.room.join`
- `jido.chat.room.leave`
- `jido.chat.room.post`
- `jido.chat.room.message`
- `jido.chat.room.check_member`

Provider operation and fact types keep their existing `jido.chat.command.*` and
`jido.chat.*` forms unless the Core data review requires a schema version
change.

## Proposed source layout

```text
lib/
  jido_chat.ex                         Core Boundary and public Core API
  jido_chat/
    client.ex
    adapter.ex
    delivery.ex
    message.ex
    actor.ex
    content/
    rendering/
    signal/
    actions/
    plugin.ex                         Stable Integration Plugin API
    plugin/
    sensor.ex                         Stable Integration Sensor API
    sensor/
    runtime.ex                        Runtime Boundary and instance API
    runtime/
      room.ex
      participant.ex
      connection.ex
      bridge.ex
      storage.ex
      storage/commit.ex
      storage/history.ex
      storage/links.ex
      storage/outbox.ex
      storage/rooms.ex
      storage/memory.ex
      signals/
      actions/
```

Do not place a Core module under `plugin/`, `sensor/`, or `runtime/`. Process
modules in the root namespace are limited to the existing Plugin and Sensor
public groups.

## Implemented build order

1. Add and configure Boundary. Make the current Core and Integration code pass
   the new dependency rules.
2. Restore the small stateless Core data contract and use it in command and fact
   schemas.
3. Define the small storage capability contracts and Memory conformance suite.
4. Test one Room post across Jido commit, Chat storage, and Bus publication
   failure points. Resolve or record each Jido friction point before more
   Runtime work.
5. Keep `Jido.Chat.Plugin`, `Jido.Chat.Sensor`, and their child modules as the
   public Integration API. Add the architecture tests required by this layout.
6. Move only the Room, Participant, Connection definition, and Bridge domain
   parts of the current small Messaging implementation into Runtime. Use the
   required host Jido instance. Rename all modules and Signal types. Do not move
   `lib_old/`.
7. Upgrade room messages and bridge translation to preserve actor and content
   data.
8. Verify room-only, Integration-only, two-account, bridge, storage failure,
   backpressure, and account-restart paths.
9. Update the public API, source layout, examples, contracts, and package
   description.

Each step must pass tests, format checks, warnings-as-errors, Boundary, Credo,
Dialyzer, and documentation checks.

## Vetted architecture decisions

| Item | Decision | Reason and guard |
|---|---|---|
| One package | Accepted | Core, Integration, and Runtime share chat values and contracts. Boundary enforces their dependency direction. |
| Core root namespace | Accepted | `Jido.Chat.*` remains the public SDK. Process modules in the root namespace are limited to the stable Plugin and Sensor groups. |
| Required Jido instance | Accepted | The host supplies one Jido v3 instance. Chat adds no Agent supervisor, Registry, Router, or private Jido child. |
| Application startup | Accepted | `:jido_chat` starts no process, Repo, table, room, Sensor, or queue. |
| Core data model | Accepted with a scope gate | Restore only portable Actor, Message, Content, Media, Post, and AI history values required by provider and Runtime contracts. |
| Integration Plugin names | Accepted | Keep `Jido.Chat.Plugin`, `Jido.Chat.Sensor`, and their child modules. Use the Jido Plugin lifecycle, admission, Directives, and readiness. Provider secrets remain runtime-only. |
| Provider Sources | Accepted with ownership guard | Provider packages own polling, gateways, reconnect, acknowledgements, and protocol cursors. Integration owns only Agent attachment. |
| Room Agent | Accepted | Room policy, admission, sequence, and a bounded working set fit Jido Plugin state. Canonical durable history does not. |
| Participant Plugin | Accepted | Use Jido Bus Client and normal Agent routes. Do not add a Chat subscription manager. |
| Bridge Plugin | Accepted | Bridge mapping, origin, reply correlation, capability checks, and echo prevention are Chat domain rules. |
| Chat storage | Accepted | It is separate from Jido persistence and the Signal Bus store. It owns queryable Chat records and delivery intent. |
| Capability storage API | Accepted | Use small History, Links, Outbox, Rooms, and Commit behaviors. Do not restore the old large persistence behavior. |
| Memory adapter | Accepted | It supplies fast tests and local ephemeral use. It must pass the same capability conformance suites. |
| Optional Ecto adapter | Deferred | Do not add Ecto to the Messaging merge or the Jido Chat 3.0 acceptance gate. Plan it after the merge. |
| Ecto migrations | Deferred | Add no migration helper or database schema during this merge. |
| Old stored data | Rejected | There is no compatibility or data migration from `jido_messaging`. |
| Provider Outbox | Accepted | It is domain storage for recoverable provider intent. An account Plugin runtime owns bounded claims and execution. It is not a generic job system. |
| Automatic provider retry | Rejected | Submitted, failed, completed, and unknown work is never sent again without explicit reconciliation or host policy. |
| Signal Bus | Accepted | Use Jido Bus Manager and Client Plugins. The Bus is delivery infrastructure, not the Chat history database. |
| Signal names | Accepted | Use only `jido.chat.*` names. Do not alias `messaging.*` types. |
| Saved account definitions | Deferred | Account restoration policy and secret resolution need a separate host-facing contract. |
| Provider packages | Accepted as separate packages | They implement Core adapter and Integration Source contracts without depending on Runtime internals. |
| Hex release work | Out of scope | Package publication and `jido_messaging` retirement are handled separately. |

## Follow-up hardening gates

The merge tests the primary Runtime contract. These larger production and scale
tests remain follow-up work:

1. Finalize the Core portable maps used by Runtime Signals and storage values.
2. Prove the Room post protocol across Jido commit, Chat Commit, and Bus publish
   crashes. Record which component owns replay at each boundary.
3. Prove Outbox claim, lease, submission, and unknown-outcome transitions with
   the storage conformance suite.
4. Define hard admission and queue bounds for provider bursts and room fan-out.
   If Jido cannot expose the required pressure, change Jido rather than adding
   a hidden Chat queue.
5. Test provider Source replacement through Jido Plugin quiesce and resume
   without persisting credentials.
6. Test many Room Agents, room Buses, account Agents, and durable subscriptions
   in one Jido namespace and across partitions.
7. Confirm that a custom application adapter can replace one storage capability
   without importing unrelated storage dependencies.
