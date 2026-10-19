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
    actions/                 23 native Jido Actions; generated nested result definitions
    adapter_test_kit/         Native request fixtures and assertions
    errors/                  Safe typed errors
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
      definition.ex          Public provider fact macro and Signal construction rules
      identity.ex            Source and conversation subject keys
      policy.ex              JSON, context, and size checks
```

Telegram has flat provider Actions, native request Signals, one internal operation
implementation, a normalizer, pure membership/webhook helpers, and an injected
transport. All uploads use the same implementation. GetFile and DownloadFile use
the same file resolver. ExGram models exist only at the transport boundary.

Removed core groups: `models/`, `payloads/`, `content/`, `webhook/`. Their duplicate
data types and host records are replaced by Signal schemas or belong in Messaging.
Pure MIME and stream chunk helpers now live in `rendering/`.

Normal SDK application startup creates no Chat process, table, client registry,
request cache, or listener. The host can explicitly start a Sensor or declare
`Jido.Chat.Plugin` on an Agent. AgentServer then owns the Plugin and input
processes. These optional processes hold only activation state and bounded input
identities. Durable offsets, message history, queues, subscription records,
identity mapping, persistence, and Bus supervision remain host or Messaging work.

See [Agent connections and sources](agent_plugin.md) for the optional runtime
boundary. A stream renderer still returns a value for the caller to retain.

See [the full public API](public_api.md). This is a breaking v3 change.
Active Covenant contracts are in `test/contracts`; see [the contract guide](contracts.md).
