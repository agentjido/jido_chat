---
modules: [Jido.ChatAction]
---
# Native chat Actions

## Purpose

Define the observable actions boundary for the stateless Jido Chat SDK.
Tests use public functions and independent fixtures. The host owns the messaging runtime.

### jido_chat.actions.I1 — Every core operation executes as a Jido Action
- **scope:** The 23 core request and Action pairs in the reviewed catalog.
- **must:** Accept a native request at params.signal with a private Client context. Execute through Jido.Exec. Return a native completion at output.signal and validate the canonical provider result. All core Actions must work for two client identities.
- **kind:** functional
- **status:** retired

### jido_chat.actions.I2 — Invalid or foreign requests never reach the provider
- **scope:** Wrong types, schema identities, clients, subjects, references, data, and private context.
- **must:** Validate the exact request definition, JSON data, client identity, conversation subject, and all portable references before provider I/O. Reject input from a different operation or client.
- **kind:** security
- **status:** active

### jido_chat.actions.I3 — Invalid provider results cannot become completions
- **scope:** Malformed results, wrong rooms, foreign nested references, and private result values.
- **must:** Return the matching invalid_provider_result Failed Signal with outcome unknown. Never emit an invalid success or include private provider data.
- **kind:** security
- **status:** active

### jido_chat.actions.I4 — Failures preserve safe categories and causal context
- **scope:** Rejected, not-attempted, unknown, raised, and thrown provider failures.
- **must:** Return Jido.Chat.Error with the matching Failed Signal. Preserve client_id, request_id, operation, traceparent, tracestate, and jidocausationid. Expose only declared safe codes, outcomes, and a non-negative retry_after_ms hint. Never expose raw provider errors.
- **kind:** security
- **status:** active

### jido_chat.actions.I5 — Actions compose through native Jido primitives
- **scope:** Jido.Flow, Signal Router, Instruction, Exec, and Dispatch.
- **must:** Run ordered dependent steps through the same Action and Signal boundary. Route a typed request to an Instruction and dispatch its native completion. The host owns publication and any Bus process.
- **kind:** ordering
- **status:** active

### jido_chat.actions.I6 — Agent discovery describes the accepted wire format
- **scope:** Each Action to_json input and output schema and serialized request input.
- **must:** Describe the full Signal envelope and exact typed data. Pin request and completion type and dataschema identities. Accept serialized request envelopes through Exec and reject envelope fields or data outside the declared contract.
- **kind:** persisted-format
- **status:** retired

### jido_chat.actions.I7 — Every core operation uses shared Signal data schemas
- **scope:** The 23 core request and Action pairs in the reviewed catalog.
- **must:** Accept request data with private Client context. Execute through Jido.Exec and return validated completion data. Build the correlated completion Signal with reply/3. All core Actions must work for two client identities.
- **kind:** functional
- **status:** active

### jido_chat.actions.I8 — Agent discovery describes native Action data
- **scope:** Each Action to_json input and output schema and serialized request data.
- **must:** Describe the exact request and completion data schemas. Use the same schemas for native Action validation and Signal data. Accept serialized request data through Exec. Preserve the reviewed Signal identities and wire schemas at the SDK boundary.
- **kind:** persisted-format
- **status:** active
