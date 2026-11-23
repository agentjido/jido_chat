# Jido.Chat

A chat SDK and optional Jido Runtime for Elixir. Use immutable clients, native
Jido Signals, and Jido Actions to call chat providers. Use
`Jido.Chat.Runtime` for durable Room records, declarations, membership, message
history, reactions, local Room Agents, participants, provider account
declarations, bridge bindings, and one application-wide Signal Bus. The host
owns the Jido instance, secret resolver, storage processes, and presence system.

See the [full static SDK API](guides/static_sdk.md) for all 23 Actions, 86 Signals, provider contracts, Flow and Router examples, and the breaking migration.

See the [current public API reference](guides/public_api.md) for the Core SDK and
provider contracts.

See the [Agent Plugin and shared Sensor](guides/agent_plugin.md) for explicit Agent connections, plain routes, and provider sources. These processes start only when the host activates them.

See the [Runtime guide](guides/runtime.md) for the optional managed process tree,
rooms, participants, provider accounts, bridge mappings, storage, and recovery.
It also describes Runtime-wide realtime subscriptions and the host presence
boundary.

See the [storage adapter guide](guides/storage_adapters.md) for durable Room
records and runtime state, DETS storage, and framework-neutral Ecto or Ash
resource adapters.

See the [source layout](guides/source_layout.md) for module groups and removed APIs.

The example uses the default Telegram transport. Add `:ex_gram` and `:req` to the host app.

```elixir
client = Jido.Chat.Client.new!(Jido.Chat.Telegram.Adapter,
  id: "support",
  credentials: %{token: token}
)

{:ok, result_signal} = Jido.Chat.send_text(client, "12345", "Hello")
message_id = result_signal.data["result"]["id"]
{:ok, edited} = Jido.Chat.edit_message(client, "12345", message_id, "Updated")
{:ok, reacted} = Jido.Chat.add_reaction(client, "12345", message_id, "👍")

Jido.Chat.capabilities(client) # canonical operation names, :native or :unsupported
```

The main functions are `send_text`, `stream_text`, `send_file`, `edit_message`,
`delete_message`, `download_file`, `add_reaction`, `remove_reaction`, `fetch_metadata`,
`start_typing`, and `create_thread`. Each runs
an existing Action with a request Signal and returns a completion Signal.
Capability discovery reads local adapter declarations without I/O.

Telegram, Discord, Slack, Signal Messenger, and X are part of `jido_chat`.
Add the optional transport dependencies for the features you use. See
[provider setup and migration](guides/providers.md).

Starting `:jido_chat` starts no process, table, room, queue, or storage resource.
Core and `Jido.Chat.Plugin` continue to work without Runtime.

Core and provider operations use native `Jido.Action` modules. Provider adapters
register their Actions and typed Signals with `operation_definitions/0` and
register incoming facts with `event_definitions/0`. `Jido.Chat.execute/3` runs
core and provider requests. Main helpers accept `timeout:` in milliseconds and
`options:` for private transport options. Native Exec calls return data, and
the SDK builds the completion Signal. See the [public API guide](guides/public_api.md)
for a provider extension example.

This major release removes Binding, Resources, RequestStore, and Handlers. Covenant contracts now define the public API, Actions, Signals, and adapter boundary. Run `mix test.contracts`; see the [contract guide](guides/contracts.md).

Files use one `source` schema across core and Telegram Actions. Keyboards are
validated Signal data. Duplicate domain records and raw helper APIs are removed.
See the [current API and migration boundary](guides/public_api.md).
