# Jido.Chat Parity Matrix (Phase 2 Completion Batch)

This matrix tracks practical parity against the Vercel Chat SDK surface using explicit capability classes:

- `native`: platform/adapter implements direct behavior.
- `fallback`: behavior is provided via a deterministic fallback path.
- `unsupported`: explicit typed unsupported behavior (`{:error, :unsupported}`).

## Core (`jido_chat`)

| Surface | Status |
|---|---|
| `Jido.Chat` lifecycle + routing (`new/initialize/shutdown`, mention/message/subscribed) | native |
| Typed event routing (`process_event/4` + `process_*` wrappers) | native |
| Typed webhook API (`handle_webhook_request/4`, `webhooks/1`) | native |
| Serialization/revival (`to_map/from_map/reviver`) for core handles | native |
| Thread/channel state helpers (pure struct) | native |
| `Thread`/`ChannelRef` stream helpers | native |
| `SentMessage` lifecycle (`edit/delete/reactions`) | native |
| Adapter capability matrix + conformance validation | native |

## Telegram (`jido_chat_telegram`)

| Capability | Status | Notes |
|---|---|---|
| send/edit/delete message | native | ExGram transport |
| typing | native | `sendChatAction` |
| metadata fetch | native | `getChat` |
| open DM | native | Telegram user/chat id model |
| reactions add/remove | native | `setMessageReaction` |
| webhook secret verification | native | `x-telegram-bot-api-secret-token` |
| parse webhook event families (`message`, `edited_message`, `callback_query`, `message_reaction`) | native | normalized to typed events |
| ephemeral message | fallback | DM fallback path |
| message history (`fetch_messages`, `fetch_channel_messages`) | unsupported | Bot API limit in this adapter scope |
| thread listing (`list_threads`) | unsupported | platform/model mismatch |
| modal APIs | unsupported | no native Telegram modal surface |

## Discord (`jido_chat_discord`)

| Capability | Status | Notes |
|---|---|---|
| send/edit/delete message | native | Nostrum transport |
| typing | native | channel typing API |
| metadata/thread/message fetch | native | normalized outputs |
| reactions add/remove | native | message reaction API |
| list threads | native | normalized thread page |
| webhook interaction parsing (slash/action/modal submit) | native | typed event envelopes |
| gateway helper routing (message/reaction/modal close) | native | forwards to `process_*` |
| signature verification | native | Ed25519 + timestamp fail-closed path |
| interaction ephemeral | native | interaction response flags |
| fallback ephemeral (non-interaction) | fallback | DM fallback |
| modal close (webhook-native) | unsupported | handled as synthetic gateway event |

## Migration Notes

- `Jido.Chat.Message` is the normalized Chat SDK-style message object.
- legacy model remains available as `Jido.Chat.LegacyMessage` for migration.
- compatibility wrappers (`Jido.Chat.Telegram.Channel`, `Jido.Chat.Discord.Channel`) are retained for this phase.
