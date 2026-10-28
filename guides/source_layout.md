# Source layout

Public Actions keep flat names. `actions/send_message.ex` defines
`Jido.Chat.SendMessage`. File groups do not add a public namespace.

```text
lib/
  jido_chat.ex                Client execution, normalization, and catalog
  jido_chat_action.ex         Native Jido Action composition macro
  jido_chat_action/
    execution.ex             Request/result validation and trace inheritance
  jido_chat/
    adapter.ex               Stateless provider behaviour and pure render helpers
    client.ex                Immutable credentials and transport configuration
    delivery.ex              Ordered native incoming Signals
    actor.ex                 Portable message actor
    content.ex               Portable text, Markdown, media, file, and tool content
    file_source.ex           Portable provider reference, URL, or base64 source
    media.ex                 Portable media attachment
    message.ex               Portable normalized message snapshot
    post.ex                  Portable local or provider post request
    resource_ref.ex          Portable provider resource reference
    ai.ex                    AI message conversion
    actions/                 23 native Jido Actions; generated nested result definitions
    adapter_test_kit/         Native request fixtures and assertions
    errors.ex                Splode error definitions and handler
    internal/                Schema and serialization helpers
    operations/              Core operation definitions and result schemas
    plugin.ex                Agent Chat DSL and explicit connection scope
    plugin/                  DSL entities, post-commit delivery, and activation state
    sensor.ex                Host-owned poll or push input and Signal Dispatch
    sensor/source.ex         Provider input behaviour
    rendering/               Markdown, cards, modals, emoji, MIME, stream chunks
    signal/
      commands/              13 command definitions
      queries/               10 query definitions
      events/                17 incoming event definitions
      schemas.ex             Shared result, file source, and keyboard schemas
      identity.ex            Source and conversation subject keys
      policy.ex              Signal construction, tracing, JSON, context, and size checks
    runtime.ex               Host-owned Runtime facade
    runtime/
      room.ex                Local Room Agent and Bus identity
      participant.ex         Room observation and reply Plugin
      connection.ex          Provider account activation through host Jido
      bridge.ex              Provider-room to local-room Bridge Plugin
      actions/               Room, participant, and Bridge Actions
      signal/room.ex         jido.chat.room.* Signals
      storage.ex             Storage selection and capability validation
      storage/               History, Links, Outbox, Rooms, Commit, and Memory
```

Telegram has flat provider Actions, native request Signals, one internal operation
implementation, a normalizer, pure membership/webhook helpers, and an injected
transport. All uploads use the same implementation. GetFile and DownloadFile use
the same file resolver. ExGram models exist only at the transport boundary.

Removed core groups: `models/`, `payloads/`, `content/`, `webhook/`. Their duplicate
data types and host records are replaced by Signal schemas and the small portable
Core values.
Pure MIME and stream chunk helpers now live in `rendering/`.

Normal SDK application startup creates no Chat process, table, client registry,
request cache, or listener. The host can explicitly start a Sensor or declare
`Jido.Chat.Plugin` on an Agent. AgentServer then owns the Plugin and input
processes. These optional processes hold only activation state and bounded input
identities. `Jido.Chat.Runtime` adds explicit local Room, Participant, account,
Bridge, and storage contracts. The host starts its Jido instance and selected
storage resource. Runtime starts only under host-requested Agent activations.

See [Agent connections and sources](agent_plugin.md) for Integration. See the
[Runtime guide](runtime.md) for rooms and bridges. A stream renderer still
returns a value for the caller to retain.

See [the full public API](public_api.md). This is a breaking v3 change.
Active Covenant contracts are in `test/contracts`; see [the contract guide](contracts.md).
