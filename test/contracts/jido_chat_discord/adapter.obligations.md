---
modules: [Jido.Chat.Discord, Jido.Chat.Discord.Adapter, Jido.Chat.Discord.Operations]
---
# Discord adapter contract

## Purpose

Tests use fixed expectations and a recording transport. Live checks are separate.

### jido_chat_discord.adapter.I1 — Discovery has a fixed public surface
- **scope:** Public adapter boundary.
- **must:** Discovery exposes the three native Actions and all 23 explicit core capability states without provider I/O.
- **kind:** functional
- **status:** active

### jido_chat_discord.adapter.I2 — Unsupported operations do no I/O
- **scope:** Public adapter boundary.
- **must:** All seven unsupported requests return matching Failed Signals with unsupported and not_attempted.
- **kind:** functional
- **status:** active

### jido_chat_discord.adapter.I3 — Clients stay isolated
- **scope:** Public adapter boundary.
- **must:** The same Action keeps client tokens, transport calls, provider IDs, request IDs, and causal context separate.
- **kind:** functional
- **status:** active

### jido_chat_discord.adapter.I4 — Provider paths are fixed
- **scope:** Public adapter boundary.
- **must:** Core and native operations use the independently specified provider routes and exact result identities.
- **kind:** functional
- **status:** active
