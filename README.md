# Jido.Chat

[![Hex.pm](https://img.shields.io/hexpm/v/jido_chat.svg)](https://hex.pm/packages/jido_chat)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/jido_chat/)
[![CI](https://github.com/agentjido/jido_chat/actions/workflows/ci.yml/badge.svg)](https://github.com/agentjido/jido_chat/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/jido_chat.svg)](https://github.com/agentjido/jido_chat/blob/main/LICENSE)
[![Website](https://img.shields.io/badge/website-jido.run-0f172a.svg)](https://jido.run)
[![Ecosystem](https://img.shields.io/badge/ecosystem-jido.run-0ea5e9.svg)](https://jido.run/ecosystem)
[![Discord](https://img.shields.io/badge/discord-join-5865F2.svg?logo=discord&logoColor=white)](https://jido.run/discord)

`jido_chat` owns the shared typed Signal contract, adapter bindings, retained
chat value builders and deterministic fallback behavior. Messaging owns runtime
processes, grants, persistence, routing, retries and delivery acceptance.

## Release status

This branch proposes Chat 2.0. It changes the released communication API.
Use the immutable review commits while the new packages are unpublished.
Production publication requires compatible upstream Signal releases. The
published Signal beta does not contain the Catalog and router DSL used here.

## Public contract

Bind a protocol-1 adapter once with private configuration. Create a command or
query with the corresponding `Jido.Chat.Signal` definition. Use
`Jido.Chat.execute/2` to obtain a typed OperationCompleted or OperationFailed
result. Use `Jido.Chat.normalize_event/2` to obtain one complete validated
`Jido.Chat.Delivery`. Messaging accepts that delivery without changing its
parent facts.

```elixir
{:ok, binding} = Jido.Chat.bind(adapter_module, private_binding_options)
request = Jido.Chat.Signal.SendMessage.new!(%{
  "request_id" => "request-1",
  "room_id" => provider_room_id,
  "text" => "Hello"
})
{:ok, result} = Jido.Chat.execute(binding, request)
```

The application supplies the adapter, private options and provider room ID.
The complete runnable example uses a deterministic local transport:

```sh
cd integration
MIX_ENV=test JIDO_INTEGRATION_PROFILE=all JIDO_INTEGRATION_AI=0 mix deps.get
MIX_ENV=test JIDO_INTEGRATION_PROFILE=all JIDO_INTEGRATION_AI=0 mix run examples/native_contract.exs
```

Check out Messaging and all eight adapters as sibling directories before
running the complete integration project. No live provider call is required.

## Records, identity and resources

Pure message, room, participant, card, modal and Markdown builders remain as
listed in the API map. Provider credentials, transport clients, stream handles
and interaction tokens stay private. Public resource references have binding,
actor and owner scope. Expiry, cancellation and provider failures have typed
results.

A trusted application resolver supplies stable Author.id values. Adapters do
not infer framework identity from a provider ID, name or email. Membership facts
are observations; explicit runtime actions own membership, grants and presence.

## Adapter requirements

Implement protocol version 1, capture private binding configuration and declare
all operation capabilities. Normalize complete provider input units in order.
Keep native, fallback and unsupported behavior explicit. Validate every item,
size limit and resource before side effects. Follow the declared acknowledgement,
sink rejection and checkpoint rules. Adapter callbacks remain implementation
hooks behind the typed public boundary.

## Migration and checks

See [the migration guide](https://github.com/agentjido/jido_chat/blob/codex/public-signal-v3/docs/migration/MIGRATION_GUIDE.md) for consumer changes,
[the API map](https://github.com/agentjido/jido_chat/blob/codex/public-signal-v3/docs/migration/api-map.json) for retained and removed interfaces,
and [the adapter matrix](https://github.com/agentjido/jido_chat/blob/codex/public-signal-v3/docs/migration/adapter-matrix.json) for support claims.
The goal covers eight adapters; Mattermost is excluded by user instruction.

Run `mix test`, `mix quality`, and `mix docs`. The separate integration project
checks both runtime profiles and the complete provider contract. Publication
order and exact rollback pins are in the migration evidence.
