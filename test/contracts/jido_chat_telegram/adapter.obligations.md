---
modules: [Jido.Chat.Telegram, Jido.Chat.Telegram.Adapter]
---
# Telegram adapter

## Purpose

Define the Telegram implementation of the stateless Jido Chat adapter boundary.
The host owns workers, polling, acknowledgements, offsets, storage, and retries.
Contract tests use fake credentials and a recording transport. Live tests are separate.

### jido_chat_telegram.adapter.I1 — Discovery and clients have a fixed stateless boundary
- **scope:** Public adapter exports, capabilities, extensions, admitted events, and application metadata.
- **must:** Preserve the reviewed public exports. Declare twelve native core operations and all other core operations unsupported. Add fourteen provider Actions and ten admitted incoming event definitions without changing the core catalog. Client creation and discovery must perform no transport call. Keep two client identities and credentials separate. Declare no application callback, registered process, or Messaging dependency.
- **kind:** functional
- **status:** active

### jido_chat_telegram.adapter.I2 — Core Actions use explicit Telegram requests
- **scope:** Supported core operations, direct addressing, rich text, routing, keyboards, and unsupported calls.
- **must:** Execute supported core requests through the shared Action boundary. Preserve provider IDs and room identity. Map content, thread, reply, and keyboard fields from the request Signal. Reject unsupported operations before transport I/O. Reject legacy content options instead of letting them bypass the Signal schema.
- **kind:** ordering
- **status:** active

### jido_chat_telegram.adapter.I3 — Core files and Telegram media use one portable boundary
- **scope:** Core SendFile and DownloadFile, provider media Actions, and GetFile.
- **must:** Accept client-scoped file, URL, and media references or inline base64 bytes. Preserve exact upload bytes and the provider file ID. Share canonical reference and file metadata behavior across core and provider Actions. Validate file metadata before a download. Return downloaded bytes as base64 without exposing a token URL.
- **kind:** persisted-format
- **status:** active

### jido_chat_telegram.adapter.I4 — Incoming updates become ordered scoped facts
- **scope:** All ten admitted event types, messages, edits, reactions, callbacks, membership, slash commands, and topics.
- **must:** Preserve update order, stable delivery and item identities, configured client source, and conversation subject. Keep full message text and canonical sender, reply, media, and thread fields. Project only declared safe fields. Represent malformed or unsupported items as NormalizationFailed facts in place. Reject an invalid complete delivery instead of returning a partial result.
- **kind:** functional
- **status:** active

### jido_chat_telegram.adapter.I5 — Pulling updates returns explicit host state
- **scope:** FetchUpdates and direct normalization of the same batch.
- **must:** Make one getUpdates call using only the supplied offset, limit, timeout, and allowed_updates. Return the same ordered facts as direct normalization and max update_id plus one as next_offset. Preserve the supplied offset for an empty batch, or null if absent. Do not acknowledge a second batch, retain offsets, or schedule another read.
- **kind:** ordering
- **status:** active

### jido_chat_telegram.adapter.I6 — Stream delivery is explicit and bounded by the call
- **scope:** Core stream_text using Telegram auto, draft, and edit delivery.
- **must:** Use drafts for positive private IDs in auto mode and edits for other rooms. Respect client configuration and call overrides. Read the source once, close it, preserve final text, and retain one provider message ID for edit delivery. Coalesce intermediate writes and always flush final content. Stop after the first failed write without a retry, mode change, or second source read. Reject invalid delivery modes before reading the source.
- **kind:** ordering
- **status:** active
