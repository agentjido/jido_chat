# Jido.Chat Migration Notes

This package is still pre-1.0, so parity work is allowed to make breaking changes when it improves the long-term contract.

## Breaking Changes For Adapter Authors

1. `Jido.Chat.StateAdapter` now requires three new callbacks:
   - `lock/5`
   - `release_lock/3`
   - `force_release_lock/2`
2. State adapter snapshots must now round-trip `locks` and `pending_locks` alongside subscriptions, dedupe state, thread state, and channel state.
3. `Jido.Chat.Adapter.post_message/4` is now the canonical outbound entry point. Adapters should expect `Jido.Chat.PostPayload` values that may include text, markdown, cards, streams, attachments, and `Jido.Chat.FileUpload` values.
4. Capability declarations should be explicit. Adapter packages should declare the surfaces they support in `capabilities/0`, especially for `send_file`, `stream`, `open_modal`, `cards`, `modals`, `multi_file`, `post_ephemeral`, and `assistant_events`.

## Scope Clarification

- `jido_chat` is the adapter/data-model package. It owns canonical structs, adapter contracts, typed handles, and fallback behavior.
- `jido_messaging` is the runtime/orchestration layer. It owns supervision, ingress plumbing, delivery queues, retries, room/session state, and bridge lifecycle.
- `Jido.Chat.StateAdapter` and `Jido.Chat.Concurrency` still exist in `jido_chat` today so the lightweight `Jido.Chat` facade can run locally or embedded without a larger runtime.
- Do not treat `jido_chat` as the long-term production process-tree package. That is outside this package's intended scope.

## New Core Surfaces

- `Jido.Chat.Markdown`
- `Jido.Chat.Card`
- `Jido.Chat.Modal`
- `Jido.Chat.ModalResponse`
- `Jido.Chat.StreamChunk`
- `Jido.Chat.Concurrency`
- `Jido.Chat.AI`

## Behavioral Notes

- Single-upload payloads can fall back through `send_file/3` with caption and metadata preserved.
- Multi-upload payloads are still capability-gated. Without an adapter-native batch upload surface, the core package returns `{:error, :multiple_attachments_unsupported}` instead of guessing.
- Structured stream fallback now preserves step and plan text and can use placeholder-plus-edit behavior when adapters expose `edit_message/4`.
- `Jido.Chat.AI.to_messages/2` is framework-agnostic on purpose. It produces stable role/content maps without binding the package to a specific Elixir AI client or mirroring TypeScript naming exactly.
- The presence of `StateAdapter` / `Concurrency` in this package should be read as lightweight compatibility support, not as the final runtime boundary for production systems.

## Remaining Deliberate Gaps

- The core package ships lightweight concurrency hooks and an in-memory adapter, but production distributed coordination belongs in `jido_messaging`.
- Stream fallback currently collapses structured chunks to text; it does not attempt markdown healing or table buffering.
- Native card rendering, modal rendering, and transport-specific webhook semantics remain adapter-owned responsibilities.
