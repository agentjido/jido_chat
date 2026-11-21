---
modules: [Jido.Chat.Telegram]
---
# Telegram Signals

## Purpose

Define the public Telegram request and result catalog. Fixed fixtures contain
the reviewed identities, JSON data schemas, and valid examples. The shared Chat
Action boundary applies privacy, client, context, and encoded size checks.

### jido_chat_telegram.signals.I1 — The complete Telegram catalog has fixed identities and schemas
- **scope:** Ten commands, four queries, and twenty-eight result definitions.
- **must:** Preserve all forty-two reviewed module names, type strings, schema URNs, and JSON data schemas. Every request has one Action, one Completed definition, and one Failed definition. Keep identities unique and configured discovery complete.
- **kind:** persisted-format
- **status:** active

### jido_chat_telegram.signals.I2 — Typed data rejects missing, unknown, and invalid fields
- **scope:** Constructors for every request and result definition.
- **must:** Accept reviewed valid examples. Reject missing required fields, unknown data fields, and non-JSON runtime values in typed fields. Use the exact operation value in result envelopes. Failed Signals accept only the declared safe codes, outcomes, and non-negative retry hints.
- **kind:** functional
- **status:** active

### jido_chat_telegram.signals.I3 — Native serialization retains identity and causal context
- **scope:** All forty-two definitions through Telegram and configured Chat catalogs.
- **must:** Preserve the native Signal through JSON serialization and Catalog decoding, including trace and causation fields. Reject unknown type or schema identities. Keep Telegram extensions outside the zero-arity core Chat catalog.
- **kind:** persisted-format
- **status:** active

### jido_chat_telegram.signals.I4 — Accepted Action Signals contain only public data
- **scope:** Native and serialized Telegram requests at the shared execution boundary and generated results.
- **must:** Reject private or runtime data, unknown trace extensions, unsafe source context, and foreign client references before transport I/O. Keep credentials and transport options in private context. Output only canonical safe result data, configured source, and causal identity.
- **kind:** security
- **status:** active

### jido_chat_telegram.signals.I5 — Telegram constraints remain explicit in schemas
- **scope:** Polls, drafts, callback responses, update queries, webhooks, media sources, keyboards, and file metadata.
- **must:** Enforce documented numeric and length limits, supported source forms, caption support, and mutually exclusive button targets. Preserve false and zero values. Reject unsafe file paths, invalid base64, negative sizes, and invalid draft room IDs. Removing a keyboard uses an empty rows array on a core EditMessage request.
- **kind:** functional
- **status:** active

### jido_chat_telegram.signals.I6 — Size and batch limits apply before accepted execution or delivery
- **scope:** Encoded Telegram Action requests and normalized provider batches.
- **must:** Reject Action Signals above 262144 encoded bytes before transport I/O. Normalization must reject an oversized Signal, more than 100 facts, more than 20 failure facts, or a Delivery above 1048576 encoded bytes. Do not return a partial batch after a limit failure.
- **kind:** security
- **status:** active
