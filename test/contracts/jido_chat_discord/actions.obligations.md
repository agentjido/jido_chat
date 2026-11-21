---
modules: [Jido.Chat.Discord.RespondInteraction, Jido.Chat.Discord.SendRichMessage, Jido.Chat.Discord.StartMessageThread, Jido.Chat.Discord.Operations]
---
# Discord Action composition

## Purpose

Keep provider execution compatible with the shared Chat facade and Core V3.

### jido_chat_discord.actions.I1 — Facade helpers keep request identity
- **scope:** All eleven shared convenience helpers with Discord clients.
- **must:** Execute the corresponding core operation, preserve explicit request IDs, use fixed provider routes, return catalog-valid results, and roundtrip exact download bytes.
- **kind:** functional
- **status:** active

### jido_chat_discord.actions.I2 — Core and native Actions compose in Flow
- **scope:** A real two-step Jido.Flow executed with Jido.Exec.
- **must:** Run core SendMessage before native SendRichMessage, return both provider results, and preserve each request's causal identity.
- **kind:** ordering
- **status:** active

### jido_chat_discord.actions.I3 — Streams and uploads execute once
- **scope:** A finite resource stream and an inline binary file.
- **must:** Consume the stream once, close its resource, send one assembled message, and preserve exact binary upload bytes.
- **kind:** ordering
- **status:** active

### jido_chat_discord.actions.I4 — Provider rejection does not repeat writes
- **scope:** A confirmed rate-limit rejection.
- **must:** Return a typed Failed Signal with rejected outcome and retry delay, keep causal identity, disclose no credential, and make one transport call.
- **kind:** functional
- **status:** active

### jido_chat_discord.actions.I5 — Action admission rejects altered Signals
- **scope:** Native Action execution boundary.
- **must:** Altered private or malformed request Signals fail before transport I/O through Chat and Jido.Exec.
- **kind:** functional
- **status:** active

### jido_chat_discord.actions.I6 — Native results preserve context
- **scope:** Native Action execution boundary.
- **must:** Native Actions execute through Chat and Jido.Exec with exact causal context and catalog-valid public results.
- **kind:** functional
- **status:** active
