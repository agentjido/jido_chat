# Jido.Chat

`jido_chat` is the core Chat SDK-style surface for `Jido.Chat` adapters.

## Experimental Status

This package is experimental and pre-1.0. APIs and behavior will change.

`Jido.Chat` is an Elixir implementation aligned to the Vercel Chat SDK
([chat-sdk.dev/docs](https://www.chat-sdk.dev/docs)).

It provides:

- `Jido.Chat` as the pure struct + bot loop
- typed thread and channel handles (`Thread`, `ChannelRef`)
- canonical outbound payloads (`Postable`, `PostPayload`, `FileUpload`, `StreamChunk`)
- rich content models (`Markdown`, `Card`, `Modal`, `ModalResponse`)
- typed normalized inbound/event payloads (`Incoming`, `Message`, `SentMessage`, `Response`, `EventEnvelope`)
- explicit adapter capability negotiation and fallback behavior (`Jido.Chat.Adapter`, `CapabilityMatrix`)
- pluggable state and overlapping-message concurrency (`StateAdapter`, `Concurrency`)
- framework-agnostic AI history conversion (`Jido.Chat.AI`)

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
`Jido.Chat.ChannelRef` and `Jido.Chat.Thread` are the typed handles for room and thread operations.
Adapters can expose native rich posting through `post_message/3`, which receives the full
typed `Jido.Chat.PostPayload` including attachments. `send_file/3` remains the low-level
upload hook used by the core fallback path for single-upload posts.

## Adapter Author Checklist

1. Implement the required `Jido.Chat.Adapter` callbacks for your transport.
2. Declare explicit surface support through `capabilities/0` instead of relying on callback inference.
3. If you ship a custom `Jido.Chat.StateAdapter`, implement `lock/5`, `release_lock/3`, and `force_release_lock/2`, and persist `locks` plus `pending_locks` in snapshots.
4. Treat `Jido.Chat.PostPayload` as the canonical outbound contract. It can now carry text, markdown, raw payloads, cards, streams, attachments, and `FileUpload` values.
5. Run `mix quality` before publishing adapter changes; the core test suite now exercises stream fallback, file fallback, modal payload rendering, concurrency, and AI conversion.

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

## Additional Core Helpers

```elixir
chat =
  Jido.Chat.new()
  |> Jido.Chat.configure_concurrency(strategy: :queue)

ai_messages = Jido.Chat.AI.to_messages(history, include_names: true)
```

## Reference Docs

- [Parity Matrix](PARITY_MATRIX.md)
- [Migration Notes](MIGRATION_NOTES.md)
