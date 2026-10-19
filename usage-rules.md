# LLM Usage Rules for Jido Chat

`jido_chat` owns the core adapter contract, Signal schemas, immutable Clients, and native Jido Actions.
Commands, facts, and results use native Jido Signals. Runtime process trees, bridge supervision, queues,
and retries belong in `jido_messaging`.

## Working Rules

- Preserve the adapter boundary; do not add production process-tree concerns to this package.
- Keep public APIs documented and typed.
- Use `Jido.ChatAction` for core and provider Actions. Extensions declare a request Signal and result schema. Override `invoke/3` for provider-specific calls. Declare extension operation pairs and admitted facts through adapter callbacks. Use configured discovery and Jido.Chat.catalog(client); do not edit the core registry.
- Use Zoi schemas for Signal data and Splode errors for safe failures. Keep credentials and transport state out of Signals.
- Use explicit native/unsupported operation capabilities. Do not infer a fallback.
- Do not add a Binding, resource store, request store, listener, or mutable session.
- The host owns credential lookup, state, duplicate checks, and retry policy.
- Incoming sender IDs are provider identities. The host owns stable identity mapping.
- Normalize polling and webhook input into the same declared facts. The host owns polling offsets and loops.
- Keep live integrations out of this package unless they are excluded by default.
- Run `mix test`, `mix quality`, and `mix coveralls` before release work.
