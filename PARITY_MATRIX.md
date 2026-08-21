# Jido.Chat Package Parity Matrix

Target: functional parity with the Vercel Chat SDK adapter and data-model surfaces as of `chat` `4.38.1`.

This matrix is package-scoped. It describes what belongs in `jido_chat`, not what belongs in the full runtime stack.
It describes the final target state for issues #35 through #44. Merge this matrix only after those implementation changes are available in their owning packages.

Target status meanings:

- `native`: owned directly by `jido_chat`.
- `fallback`: owned by `jido_chat`, but completed through a deterministic fallback path.
- `transitional`: implemented in `jido_chat` today for lightweight/local use, but better owned by a higher runtime layer such as `jido_messaging` for production systems.
- `adapter-specific`: the core package defines the contract, while platform adapters decide the transport or rendering behavior.
- `unsupported`: the core package returns an explicit unsupported result instead of guessing.

## Core-Owned Surfaces

| Surface | Core Contract | Adapter Requirement | Status | Notes |
|---|---|---|---|---|
| Lightweight lifecycle and routing | `Jido.Chat`, `process_event/4`, typed handlers | normalize inbound payloads | native | pure struct/event-loop helpers, not a supervised runtime |
| Outbound payload model | `Postable`, `PostPayload`, `FileUpload`, `StreamChunk` | optional `post_message/3` for native rich delivery | native | text, markdown, raw, card, stream, attachment, file inputs |
| Single-file fallback delivery | `Adapter.post_message/4` fallback to `send_file/3` | implement `send_file/3` | fallback | caption and metadata are preserved |
| Multi-file delivery | capability gating in core | declare and implement adapter-native batch behavior | adapter-specific | otherwise returns `{:error, :multiple_attachments_unsupported}` |
| Markdown/card/modal modeling | `Markdown`, `Card`, `Modal`, `ModalResponse` | render or translate for platform UI | native | core owns canonical payload shape and fallback text |
| Modal open helpers | `Thread.open_modal/3`, `ChannelRef.open_modal/3`, event helpers | implement `open_modal/3` for native behavior | fallback | explicit `{:error, :unsupported}` when unavailable |
| Typed event envelopes | `EventEnvelope` plus normalized event structs | parse platform webhook or gateway payloads | native | event structs now carry richer thread/channel/message context |
| Stable participant identity | `Author`, `Message`, and message context fields | preserve provider user, message, room, thread, and reply identifiers | native | stable provider identity remains separate from display labels |
| Message lifecycle events | `MessageUpdatedEvent`, `MessageDeletedEvent`, and dedicated handlers | normalize provider edit and delete callbacks | native | lifecycle callbacks do not enter the new-message handler path |
| Resource and receipt contracts | typed user, subject, participant, and read-receipt adapter operations | declare native, fallback, or unsupported behavior | adapter-specific | core owns normalized results and safe unsupported responses |
| Adapter conformance kit | `Jido.Chat.AdapterTestKit` | adopt shared factories, assertions, and capability-gated checks | native | packaged with HexDocs so adapter packages do not copy test helpers |
| Stream posting | `PostPayload.stream/2`, `Adapter.stream/4`, `Markdown.StreamRenderer` | optional `stream/3` for native streaming | fallback | partial edits repair split Markdown; final output preserves supported Markdown exactly |
| Bounded burst handling | `Concurrency`, `MessageContext`, and `StateAdapter` burst callbacks | custom state adapters for local or embedded use | transitional | debounce, TTL, queue, overflow, and concurrency bounds stay lightweight; durable queues belong in `jido_messaging` |
| Extended cards and modals | chart and table cards; link IDs; date, number, and external-select inputs | translate supported controls and enforce provider limits | adapter-specific | core owns deterministic text fallbacks and typed option-load results |
| Serialization/revival | `to_map/from_map`, `Serialization.revive/1` | preserve adapter module identity | native | typed structs round-trip; runtime state ownership is transitional |
| Capability negotiation | `CapabilityMatrix`, `Capabilities`, `Adapter.validate_capabilities/1` | declare explicit statuses in `capabilities/0` | native | native/fallback/unsupported are surfaced intentionally |
| AI history conversion | `Jido.Chat.AI.to_messages/2` | none | native | structurally compatible with Chat SDK / AI SDK message shapes, but intentionally Elixir-native |

## Runtime-Owned Outside This Package

| Surface | Runtime Owner | Notes |
|---|---|---|
| Supervision tree and process lifecycle | `jido_messaging` | bridges, rooms, agents, reconnect workers, partitions |
| Webhook Plug / HTTP ingress | `jido_messaging` | `jido_chat` should stay transport-agnostic |
| Outbound queueing, retries, backpressure | `jido_messaging` | not part of the adapter contract |
| Room/participant/thread resolution | `jido_messaging` | application/runtime concern |
| Participant-scoped cross-platform history | `jido_messaging` | one chronological transcript over authorized rooms, with filters, cursors, deletion, and AI conversion |
| Scoped chat actions | `jido_messaging` | reader, messenger, and moderator `Jido.Action` sets resolve adapters from canonical targets |
| Conversation scope and approval policy | `jido_messaging` | channel, thread, strict-thread, and workspace scopes; visible writes require approval by default |
| Session routing, moderation, onboarding, security | `jido_messaging` | orchestration and policy layer |
| Production persistence and distributed coordination | `jido_messaging` | `jido_chat` only ships lightweight hooks today |

## Adapter-Owned Responsibilities

| Surface | Why It Stays Adapter-Owned | Notes |
|---|---|---|
| Native card rendering | platform UI primitives differ too much | core provides canonical card payloads and fallback text |
| Native modal rendering and submit semantics | modal transport and response contracts are platform-specific | core owns modal payloads and lifecycle result types |
| Webhook verification and signature policy | each provider defines its own transport security model | core provides typed request/response wrappers |
| Thread/message/channel fetch details | pagination and identifiers are provider-specific | core owns normalized output structs |
| Reactions, typing, DM open, thread open/list | transport operations vary by provider | capability matrix exposes native vs fallback support |
| Option loading and provider input limits | platforms use different search APIs and limits | core owns typed option-load events/results; adapters own API calls, timeouts, and maxima |

## Remaining Deliberate Gaps

The parity program is tracked in [issue #45](https://github.com/agentjido/jido_chat/issues/45), with implementation work in issues #35 through #44.

- `jido_chat` keeps lightweight bounded concurrency hooks and the in-memory state adapter. Durable queue and distributed coordination semantics remain in `jido_messaging`.
- Platform-native cards, modals, option loading, resource fetches, and read receipts remain adapter-specific. Core returns deterministic fallbacks or explicit unsupported results.
- Live provider validation remains an adapter release gate when it needs credentials, a linked device, or a paid provider account.
