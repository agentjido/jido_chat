# LLM Usage Rules for Jido Chat

`jido_chat` owns the core adapter contract, typed chat models, and deterministic
adapter fallback behavior. Runtime process trees, bridge supervision, queues,
and retries belong in `jido_messaging`.

## Working Rules

- Preserve the adapter boundary; do not add production process-tree concerns to this package.
- Keep public APIs documented and typed.
- Use Zoi-backed structs and Splode errors for new core data and errors.
- Prefer explicit adapter capability declarations over inference.
- Keep live integrations out of this package unless they are excluded by default.
- Run `mix test`, `mix quality`, and `mix coveralls` before release work.
