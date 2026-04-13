# Jido.Chat Parity Matrix

Target: functional parity with the Vercel Chat SDK core surfaces as of `chat` `4.25.0`.

Status meanings:

- `native`: owned directly by `jido_chat`.
- `fallback`: owned by `jido_chat`, but completed through a deterministic fallback path.
- `adapter-specific`: the core package defines the contract, while platform adapters decide the transport or rendering behavior.
- `unsupported`: the core package returns an explicit unsupported result instead of guessing.

## Core-Owned Surfaces

| Surface | Core Contract | Adapter Requirement | Status | Notes |
|---|---|---|---|---|
| Lifecycle and routing | `Jido.Chat`, `process_event/4`, typed handlers | normalize inbound payloads | native | mention, message, slash, action, reaction, modal, assistant events |
| Outbound payload model | `Postable`, `PostPayload`, `FileUpload`, `StreamChunk` | optional `post_message/3` for native rich delivery | native | text, markdown, raw, card, stream, attachment, file inputs |
| Single-file fallback delivery | `Adapter.post_message/4` fallback to `send_file/3` | implement `send_file/3` | fallback | caption and metadata are preserved |
| Multi-file delivery | capability gating in core | declare and implement adapter-native batch behavior | adapter-specific | otherwise returns `{:error, :multiple_attachments_unsupported}` |
| Markdown/card/modal modeling | `Markdown`, `Card`, `Modal`, `ModalResponse` | render or translate for platform UI | native | core owns canonical payload shape and fallback text |
| Modal open helpers | `Thread.open_modal/3`, `ChannelRef.open_modal/3`, event helpers | implement `open_modal/3` for native behavior | fallback | explicit `{:error, :unsupported}` when unavailable |
| Typed event envelopes | `EventEnvelope` plus normalized event structs | parse platform webhook or gateway payloads | native | event structs now carry richer thread/channel/message context |
| Stream posting | `PostPayload.stream/2`, `Adapter.stream/4` | optional `stream/3` for native streaming | fallback | placeholder-plus-edit fallback uses `edit_message/4` when present |
| Overlapping-message concurrency | `Concurrency`, `StateAdapter`, chat-level lock helpers | custom state adapters for distributed coordination | native | memory adapter supports reject, queue, debounce, concurrent |
| Serialization/revival | `to_map/from_map`, `Serialization.revive/1` | preserve adapter module identity | native | snapshots now include lock state |
| Capability negotiation | `CapabilityMatrix`, `Capabilities`, `Adapter.validate_capabilities/1` | declare explicit statuses in `capabilities/0` | native | native/fallback/unsupported are surfaced intentionally |
| AI history conversion | `Jido.Chat.AI.to_messages/2` | none | native | chronological sorting, role mapping, multipart attachment conversion |

## Adapter-Owned Responsibilities

| Surface | Why It Stays Adapter-Owned | Notes |
|---|---|---|
| Native card rendering | platform UI primitives differ too much | core provides canonical card payloads and fallback text |
| Native modal rendering and submit semantics | modal transport and response contracts are platform-specific | core owns modal payloads and lifecycle result types |
| Webhook verification and signature policy | each provider defines its own transport security model | core provides typed request/response wrappers |
| Thread/message/channel fetch details | pagination and identifiers are provider-specific | core owns normalized output structs |
| Reactions, typing, DM open, thread open/list | transport operations vary by provider | capability matrix exposes native vs fallback support |

## Remaining Deliberate Gaps

Repository tracking for parity follow-up work lives under Beadwork epic `jchat-w38`.

- `jido_chat` ships the concurrency contract and the in-memory state adapter, but not a distributed lock adapter.
- Stream fallback currently renders structured chunks to text; it does not do markdown healing or table buffering.
- Platform-native card and modal rendering remain intentionally adapter-specific even though the payload model is now shared.
