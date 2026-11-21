---
modules: [Jido.Chat.Discord.Normalizer]
---
# Discord normalization contract

## Purpose

Tests use fixed expectations and a recording transport. Live checks are separate.

### jido_chat_discord.normalization.I1 — Fact identity is stable and scoped
- **scope:** Public normalization boundary.
- **must:** Independent fixed provider events produce expected public facts, stable IDs, and client-scoped sources and subjects.
- **kind:** functional
- **status:** active

### jido_chat_discord.normalization.I2 — Interactions drop private controls
- **scope:** Public normalization boundary.
- **must:** Slash, button, and modal facts preserve public identity and values while excluding tokens and raw provider input.
- **kind:** functional
- **status:** active

### jido_chat_discord.normalization.I3 — Media references are stable
- **scope:** Public normalization boundary.
- **must:** Attachments expose scoped stable references without signed URLs.
- **kind:** functional
- **status:** active

### jido_chat_discord.normalization.I4 — Partial input is explicit
- **scope:** Public normalization boundary.
- **must:** A malformed batch item emits a safe failure without discarding valid sibling facts; repeated delivery has stable identities.
- **kind:** functional
- **status:** active
