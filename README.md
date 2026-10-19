# Jido.Chat

A stateless chat SDK for Elixir. Use immutable clients, native Jido Signals, and Jido Actions to call chat providers. The host owns the messaging runtime.

See the [full static SDK API](guides/static_sdk.md) for all 23 Actions, 86 Signals, provider contracts, Flow and Router examples, and the breaking migration.

See the [current public API reference](guides/public_api.md) for every public function, Telegram support, a two-step Flow, and the remaining Messaging boundary.

See the [Agent Plugin and shared Sensor](guides/agent_plugin.md) for explicit Agent connections, plain routes, and provider sources. These processes start only when the host activates them.

See the [source layout](guides/source_layout.md) for module groups and removed APIs.

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

Provider packages are separate dependencies. Each adapter must implement the native Signal contract. This cleanup verifies the Telegram adapter. Other adapters need migration before they can use this breaking version.

Build core or provider Actions with `use Jido.ChatAction`. Provider extensions supply
their own Signal definition and result schema. They can override `invoke/3` without
an edit to the core operation registry. Configure provider discovery with the
adapter's `operations/0` and `event_definitions/0`. `Jido.Chat.execute/3` then runs
core and provider requests. Main helpers accept `timeout:` in milliseconds and
`options:` for private transport options. Action schemas match Signal data.
Native Exec calls return data; `reply/3` builds the completion Signal. See the full API guide for `Telegram.SendPoll`.

This major release removes Binding, Resources, RequestStore, and Handlers. Covenant contracts now define the public API, Actions, Signals, and adapter boundary. Run `mix test.contracts`; see the [contract guide](guides/contracts.md).

Files use one `source` schema across core and Telegram Actions. Keyboards are
validated Signal data. Duplicate domain records and raw helper APIs are removed.
See the [current API and migration boundary](guides/public_api.md).
