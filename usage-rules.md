# LLM Usage Rules for Jido Chat

`jido_chat` owns the core adapter contract, Signal schemas, immutable Clients, and native Jido Actions.
Commands, facts, and results use native Jido Signals. Optional rooms, participants, account Agents,
bridges, bounded provider work, and storage capabilities belong in `Jido.Chat.Runtime`.

## Working Rules

- Preserve the adapter boundary. Provider listeners, protocol cursors, and transport reconnect loops stay
  in provider packages or the host. Runtime composes Chat domain work into a host-owned Jido instance.
- Keep public APIs documented and typed.
- Use `Jido.Action` and `Jido.Chat.Operations.Definition` for provider extensions. Register the operation and admitted facts through adapter callbacks. Use configured discovery and `Jido.Chat.catalog(client)`.
- Use Zoi schemas for Signal data and Splode errors for safe failures. Keep credentials and transport state out of Signals.
- Use explicit native/unsupported operation capabilities. Do not infer a fallback.
- Do not add a hidden global Binding, listener, mutable session, storage process, or private Jido instance.
- The host owns credential lookup, storage resource startup, and retry or reconciliation policy.
- Incoming sender IDs are provider identities. The host owns stable identity mapping.
- Normalize polling and webhook input into the same declared facts. The host owns polling offsets and loops.
- Keep live integrations out of this package unless they are excluded by default.
- Run `mix test`, `mix quality`, and `mix coveralls` before release work.
