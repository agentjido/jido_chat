---
modules: [Jido.Chat]
---
# Public SDK API

## Purpose

Define the observable public api boundary for the stateless Jido Chat SDK.
Tests use public functions and independent fixtures. The host owns the messaging runtime.

### jido_chat.public_api.I1 — The documented function boundary is explicit
- **scope:** Documented SDK modules and their public function and macro arities.
- **must:** Keep the reviewed export manifest. Do not restore removed stateful APIs. Rendering helpers remain pure values, separate from provider operation support.
- **kind:** functional
- **status:** active

### jido_chat.public_api.I2 — Main helpers build and execute native Signals
- **scope:** All eleven main operation helpers, two configured clients, shared and operation-specific options.
- **must:** Generate the matching request Signal and return its Action completion. Keep content, format, routing, keyboard, request identity, and trace context in Signals. Keep credentials and transport options private.
- **kind:** functional
- **status:** active

### jido_chat.public_api.I3 — Request identity provides correlation without duplicate suppression
- **scope:** Generated and explicit request IDs through the main helpers.
- **must:** Generate a fresh valid Signal ID when omitted. Preserve an explicit request ID. Repeating an explicit ID remains a separate execution and can repeat a provider write.
- **kind:** functional
- **status:** active

### jido_chat.public_api.I4 — Invalid options fail before provider calls
- **scope:** Unknown, duplicate, malformed, or unrelated helper and execution options.
- **must:** Return a structured error before provider I/O. Accept private options only through options and accept an execution timeout in milliseconds or infinity.
- **kind:** ordering
- **status:** active

### jido_chat.public_api.I5 — Streaming sources remain private and are consumed once
- **scope:** stream_text and StreamText through a configured adapter.
- **must:** Keep the Enumerable in private Action context. Consume it once in the execution task. An unsupported operation must not consume it. Close a resource source after normal completion. Return only the final canonical message Signal.
- **kind:** security
- **status:** active

### jido_chat.public_api.I6 — Execution deadlines do not trigger automatic retries
- **scope:** execute and main helpers with a blocked provider call.
- **must:** Make one attempt. Return a timeout Failed Signal with outcome unknown when the deadline expires. Do not claim that the provider write was cancelled or safe to repeat.
- **kind:** functional
- **status:** active
