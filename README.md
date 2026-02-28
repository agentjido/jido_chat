# Jido.Chat

`jido_chat` is the core Chat SDK-style surface for `Jido.Chat` adapters.

## Experimental Status

This package is experimental and pre-1.0. APIs and behavior will change.
`Jido.Chat` is an Elixir implementation aligned to the Vercel Chat SDK
([chat-sdk.dev/docs](https://www.chat-sdk.dev/docs)).

It provides:

- `Jido.Chat` (pure struct + function bot loop)
- typed normalized payloads (`Incoming`, `Message`, `SentMessage`, `Response`, `EventEnvelope`)
- typed handles (`Thread`, `ChannelRef`)
- canonical adapter behavior (`Jido.Chat.Adapter`)

## Installation

```elixir
def deps do
  [
    {:jido_chat, github: "agentjido/jido_chat", branch: "main"}
  ]
end
```

## Canonical Adapter Interface

`Jido.Chat.Adapter` is the canonical contract for new integrations.

`Jido.Chat.Channel` remains available as a compatibility shim for legacy channel modules during migration.

## Usage (Core Loop)

```elixir
chat =
  Jido.Chat.new(
    user_name: "jido",
    adapters: %{telegram: Jido.Chat.Telegram.Adapter}
  )
  |> Jido.Chat.on_new_mention(fn thread, incoming ->
    Jido.Chat.Thread.post(thread, "hi #{incoming.display_name || "there"}")
  end)
```

## Parity Matrix

Adapter/core parity status is tracked in:

- `../PARITY_MATRIX.md`
