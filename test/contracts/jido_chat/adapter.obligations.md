---
modules: [Jido.Chat.Adapter, Jido.Chat.Client, Jido.Chat.Delivery, Jido.Chat.AdapterTestKit]
---
# Stateless adapter contract

## Purpose

Define the observable adapter boundary for the stateless Jido Chat SDK.
Tests use public functions and independent fixtures. The host owns the messaging runtime.

### jido_chat.adapter.I1 — Adapters declare explicit support and optional extensions
- **scope:** Adapter callbacks, Client construction, and capability discovery.
- **must:** Require channel_type/0, capabilities/0, invoke/3, and normalize/3. Allow default_transport/0, operations/0, and event_definitions/0. Fill missing core statuses with unsupported. Reject invalid statuses and conflicting extensions without provider I/O. Discovery performs no provider call.
- **kind:** functional
- **status:** active

### jido_chat.adapter.I2 — The same Action works through different adapters
- **scope:** Two independent adapters, two configured clients, and SendMessage.
- **must:** Return the actual provider message ID and client-scoped result context through the same Action. Keep client credentials and config separate and do not retain a current client or conversation.
- **kind:** functional
- **status:** active

### jido_chat.adapter.I3 — Unsupported requests fail without provider I/O
- **scope:** Every unsupported core operation and AdapterTestKit assertions.
- **must:** Return the matching Failed Signal with code unsupported and outcome not_attempted. Never call invoke or consume a stream source. The test kit must execute these requests and validate their results.
- **kind:** ordering
- **status:** active

### jido_chat.adapter.I4 — Provider Actions and facts extend configured discovery
- **scope:** A provider Action with its own request and result schemas and an admitted provider fact.
- **must:** Include extensions in configured operations, actions, definitions, and catalog. Execute the extension through Jido.Chat.execute and Jido.Exec. Admit declared provider facts through Delivery. Keep the zero-arity core catalog unchanged.
- **kind:** functional
- **status:** active

### jido_chat.adapter.I5 — Normalization accepts only complete scoped deliveries
- **scope:** Core and provider facts, ordered batches, invalid members, and foreign clients.
- **must:** Validate every fact against the configured catalog and admitted event set. Require a stable delivery ID, matching delivery_id, the configured client source, and the client-scoped conversation subject. Reject commands, results, undeclared facts, and partial invalid deliveries.
- **kind:** security
- **status:** active

### jido_chat.adapter.I6 — Normalization failures remain safe and do not acknowledge input
- **scope:** Adapter normalize responses, errors, exceptions, and private options.
- **must:** Call normalization once. Return a validated Delivery or a structured contract error. Reject malformed returns and suppress raw exceptions. The SDK does not acknowledge, publish, save offsets, or schedule another read.
- **kind:** functional
- **status:** active
