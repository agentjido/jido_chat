---
modules: [Jido.Chat.Discord.Signal.RespondInteraction, Jido.Chat.Discord.Signal.SendRichMessage, Jido.Chat.Discord.Signal.StartMessageThread]
---
# Discord signals contract

## Purpose

Tests use fixed expectations and a recording transport. Live checks are separate.

### jido_chat_discord.signals.I1 — Native identities stay fixed
- **scope:** Public signals boundary.
- **must:** All nine native request and result types and schema identifiers remain fixed and appear in the configured catalog.
- **kind:** functional
- **status:** active

### jido_chat_discord.signals.I2 — Construction follows Chat policy
- **scope:** Public signals boundary.
- **must:** Chat policy constructors and admission reject nested private keys, unsafe JSON, bad context, unknown or duplicate options, and encoded data above the shared limit.
- **kind:** functional
- **status:** active
