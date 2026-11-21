---
modules: [Jido.Chat.Discord.Source, Jido.Chat.Discord.GatewayWorker, Jido.Chat.Discord.Interaction]
---
# Discord source contract

## Purpose

Tests use fixed expectations and a recording transport. Live checks are separate.

### jido_chat_discord.source.I1 — Source identity is credential scoped
- **scope:** Public source boundary.
- **must:** Source declares push mode and concrete facts, hashes token identity, and starts no global application.
- **kind:** functional
- **status:** active

### jido_chat_discord.source.I2 — Private controls precede admission
- **scope:** Public source boundary.
- **must:** An explicit host sink receives scoped controls before fact admission; sink failure stops input without admission.
- **kind:** functional
- **status:** active

### jido_chat_discord.source.I3 — Private controls expire and stay private
- **scope:** Public source boundary.
- **must:** Private controls bind client, bot, room, and interaction; expire within three seconds; inspect and failed requests disclose no token.
- **kind:** functional
- **status:** active

### jido_chat_discord.source.I4 — Raw-input failures are redacted
- **scope:** Public source boundary.
- **must:** A controlled worker failure does not disclose raw private input or client credentials in OTP reports; the socket closes.
- **kind:** functional
- **status:** active
