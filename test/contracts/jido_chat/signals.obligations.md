---
modules: [Jido.Chat.Signal.Definition, Jido.Chat.Signal.Identity]
---
# Public chat Signals

## Purpose

Define the observable signals boundary for the stateless Jido Chat SDK.
Tests use public functions and independent fixtures. The host owns the messaging runtime.

### jido_chat.signals.I1 — The Signal catalog has stable identities and schemas
- **scope:** All 86 core definitions: 23 requests, 46 Action results, and 17 incoming facts.
- **must:** Match the reviewed catalog of module names, types, dataschema URNs, data schemas, and valid examples. Keep each identity unique and keep the exact core definition set. Schema changes require an explicit contract change.
- **kind:** persisted-format
- **status:** active

### jido_chat.signals.I2 — Signal data has strict string-key schemas
- **scope:** Every core Signal constructor and data schema.
- **must:** Accept valid fixtures. Reject missing required fields, unknown top-level data fields, invalid JSON values, and malformed envelope metadata. Do not coerce an invalid field into a valid request.
- **kind:** functional
- **status:** active

### jido_chat.signals.I3 — Signals cannot carry private runtime or credential data
- **scope:** Nested data, constructor metadata, trace extensions, source URI, and Signal ID.
- **must:** Reject private keys, structs, processes, functions, invalid UTF-8, unapproved context, credential-bearing source URIs, and IDs above 128 bytes. Accept only traceparent, tracestate, and causationid extensions.
- **kind:** security
- **status:** active

### jido_chat.signals.I4 — Native serialization preserves public identity and trace context
- **scope:** All core requests, results, and incoming facts.
- **must:** Serialize and decode through the native Catalog without losing public fields or trace context. Reject unknown type or dataschema identities.
- **kind:** persisted-format
- **status:** active

### jido_chat.signals.I5 — Files and keyboards share portable JSON schemas
- **scope:** SendFile, DownloadFile results, SendMessage, and EditMessage.
- **must:** Accept scoped local, URL, and media references or non-empty base64 upload content with a filename. Downloads accept valid base64 including empty files. Buttons have text and exactly one callback value or URL. Enforce 64 callback bytes, eight buttons per row, and 100 buttons per keyboard. Empty edit keyboards clear buttons.
- **kind:** functional
- **status:** active

### jido_chat.signals.I6 — Signal and delivery size limits are enforced at the boundary
- **scope:** Encoded Signals and fully validated Deliveries.
- **must:** Allow at most 262144 encoded bytes per Signal, 100 Signals and 20 NormalizationFailed facts per Delivery, and 1048576 encoded bytes per Delivery. Preserve input order. Reject the whole Delivery when any item fails.
- **kind:** security
- **status:** active
