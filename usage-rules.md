# LLM Usage Rules for Jido Chat

`jido_chat` owns the core adapter contract, typed chat models, and deterministic
adapter fallback behavior. Runtime process trees, bridge supervision, queues,
and retries belong in `jido_messaging`.

## Working Rules

- Preserve the adapter boundary; do not add production process-tree concerns to this package.
- Keep public APIs documented and typed.
- Use Zoi-backed structs and Splode errors for new core data and errors.
- Prefer explicit adapter capability declarations over inference.
- Stable identity belongs to a trusted application/runtime resolver. `Jido.Chat.Author.id` is framework-neutral stable identity; `Author.user_id` is the provider identity. Adapters must not infer `Author.id` from provider IDs, display names, usernames, or email addresses, call provider profiles to obtain it, or generate a replacement stable ID.
- Legacy messages, wire maps, and adapter payloads remain valid without author or reply enrichment. Reply context is shallow and uses only event data already present; adapters do not need a new callback or replied-message lookup.
- Keep live integrations out of this package unless they are excluded by default.
- Run `mix test`, `mix quality`, and `mix coveralls` before release work.
