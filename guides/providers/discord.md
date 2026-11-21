# Jido Chat Discord

Add `:req` for the default REST transport. Add `:mint` and `:mint_web_socket`
for the default Gateway Source. See the [provider setup guide](../providers.md)
for dependency versions.


Build a Client, then execute Chat Actions with request Signals. Client construction
starts no connection. HTTP calls use the token in that Client. The host starts
and stops each receive process.

```elixir
client = Jido.Chat.Client.new!(Jido.Chat.Discord.Adapter,
  id: "discord/test",
  credentials: %{token: System.fetch_env!("DISCORD_BOT_TOKEN")}
)

{:ok, completed} = Jido.Chat.send_text(client,
  System.fetch_env!("DISCORD_TEST_CHANNEL_ID"), "Hello from Jido")
message_id = completed.data["result"]["id"]
```

## Agent connection

Add this connection to the existing Agent `chat` block. The Agent must use
`Jido.Chat.Plugin`. Environment references are resolved when the Agent starts.
The host loads `.env`; the adapter does not load credentials in production.

```elixir
connection :discord do
  client Jido.Chat.Discord.Adapter,
    id: "discord/test",
    credentials: %{token: env("DISCORD_BOT_TOKEN")}

  rooms [env("DISCORD_TEST_CHANNEL_ID")]
  commands [Jido.Chat.SendMessage]
  source Jido.Chat.Discord.Source, emit: "jido.chat.message.received"
end
```

The shared Plugin owns `Jido.Chat.Sensor`. Use normal Agent routes for received
facts. A reply Action builds a `Jido.Chat.Signal.SendMessage` with
`context.chat.client_id`, the incoming room, and a new request ID. It emits that
command. Route `"jido.chat.command.*"` to `Jido.Chat.Plugin.Execute` with
`emits: []`. Route completion and failure Signals to host Actions as needed.
The host reply Action must filter bot messages to prevent reply loops.

## Explicit receive process

For a host without the Chat Plugin:

```elixir
{:ok, sensor} = Jido.Chat.Sensor.start_link(
  client: client,
  source: Jido.Chat.Discord.Source,
  emit: "jido.chat.message.received",
  rooms: [System.fetch_env!("DISCORD_TEST_CHANNEL_ID")],
  dispatch: {:pid, target: self()}
)
```

The Source starts one linked Mint WebSocket worker. It returns before it sends
input to the Sensor. It uses Gateway v10 JSON, heartbeats, ACK checks, session
resume, and bounded reconnect delay. It closes the socket when it stops.
It starts no Nostrum application and uses no application-wide bot token.

Default Gateway intents are `46593`: guilds, guild messages and reactions,
direct messages and reactions, and message content. The bot must have Message
Content permission in the Discord developer portal. Select other intents with
`source Jido.Chat.Discord.Source, emit: "jido.chat.**", options: [intents: value]`.
This Source uses one shard. Bots that require sharding need a different source.

`Source.key/2` hashes the token to prevent duplicate Sensors for the same token.
The Sensor checks the catalog, source, room, and emit pattern. It keeps bounded
in-memory event identities. Admission does not confirm durable storage or a
chat reply. The worker stops on rejected input. A host supervisor can restart
it, but a new worker has no saved Gateway session. No durable replay is promised.

The Source normalizes messages, edits, deletes, reactions, thread creation,
slash commands, components, and modal submissions. It learns active thread
parents from Gateway guild and thread events. A known thread uses its parent
room as `room_id` and its channel ID as `thread_id`.

Core edit, delete, reaction, and single-message query requests have no
`thread_id`. Direct SDK calls must use the thread channel as `room_id` for
these operations. A parent-scoped Agent connection needs shared request schema
support before it can use these operations within a thread.

Gateway protocol reference: [Discord Gateway documentation](https://docs.discord.com/developers/events/gateway).

## Native Discord Actions

`Jido.Chat.Discord.operations/0` returns request/Action pairs.
`signal_definitions/0` returns their request, completion, and failure definitions.
`event_definitions/0` lists incoming facts. A Client catalog includes these and
all core Chat definitions.

| Action | Use |
| --- | --- |
| `Jido.Chat.Discord.SendRichMessage` | Send embeds, native components, or TTS. |
| `Jido.Chat.Discord.StartMessageThread` | Start a thread on an existing message. |
| `Jido.Chat.Discord.RespondInteraction` | Respond, defer, update, or open a modal. |

Use each Action through `Jido.Chat.execute(client, request)`, `Jido.Exec`, or
Flow. Data uses string keys and includes `client_id` and `request_id`.
RespondInteraction requires a private `Jido.Chat.Discord.Interaction` in the
`:interaction` execution option. Its Inspect output hides all fields. Bare token
options are not supported: Core execution errors can log option values. For
Gateway input, set the explicit Source option
`interaction_sink: {HostModule, :put, [host_name]}`. The sink receives a private
`Jido.Chat.Discord.Interaction` before normalization and Signal admission. It
must return `:ok` promptly. Failure stops the Source before fact admission.

The host must own a bounded store, room checks, atomic single-use lookup, expiry,
and cleanup. Store the private value outside Signals and Agent state. Pass it to
`Jido.Chat.execute(client, request, options: [interaction: private_control])`.
Set `config: [bot_id: application_id]` on the response Client. The Action checks
the client, configured bot, room, interaction ID, and three-second initial
response deadline. The SDK has no implicit token store. The standard Agent Plugin
does not supply per-interaction private execution options. An explicit host
Action must obtain the private control and run the response. See
`test/support/providers/discord/live_interaction_host.ex`
for the bounded test composition. A replay can call the sink before Sensor
deduplication. Cleanup must also cover failed admission and shutdown.

Neither normalization nor the Source places tokens in Signals. The Source
does not acknowledge or answer interactions. For HTTP interaction input, use
`Jido.Chat.Discord.Webhook.verify(client, exact_body, headers)` before decoding
and calling `Jido.Chat.normalize/2`. For a REST response, construct the same
private control from the verified input, the configured client/bot identity, and
the local receipt time. The host owns HTTP responses and protocol ACKs.

Core Chat supports messages, files, edits, deletes, typing, reactions, direct
rooms, thread creation, message queries, metadata, and downloads. `ListThreads`
returns public archived threads. Its cursor is an archive timestamp; forward
archive scans are unsupported. Message history uses snowflake cursors and
supports forward and backward reads. Streams buffer finite chunks and send one
final message. Discord renders Markdown; HTML requests are rejected. Shared
keyboards map to Discord buttons. Discord applies its own size and row limits.

Files use inline base64 or explicit local file references. Received attachments
use stable `discord://attachment/channel/message/attachment` references.
Downloads fetch a fresh signed URL from Discord. Signed URLs and raw provider
payloads stay out of public Signals. Remote URL uploads are unsupported.

HTTP retries belong to the host. A rate limit rejection returns a failure
Signal with `retry_after_ms`. Do not repeat an operation with an unknown outcome
without a host policy for duplicate side effects.

## Validation

Use the current local Chat and Jido V3 code:

```sh
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix coveralls.json
mix test.contracts
mix covenant.check --static
RUN_LIVE_DISCORD_TESTS=true mix test test/jido_chat/providers/discord/live_api_test.exs test/jido_chat/providers/discord/live_integration_test.exs --include live
RUN_LIVE_DISCORD_UI=true mix test test/jido_chat/providers/discord/live_ui_test.exs --include live
```

Default tests exclude `:live`. The coverage gate checks production files and
requires at least 90%. Live tests require `DISCORD_BOT_TOKEN` and
`DISCORD_TEST_CHANNEL_ID`. They check the `agentjido-test` server, make temporary
messages, and delete them after the test. They test public Chat API calls and a
real Gateway → shared Sensor → V3 Agent → Chat reply path. The receive test uses
a bot-generated probe with a strict prefix so it cannot form a reply loop.


The UI suite needs the signed-in Discord app on `agentjido-test / bridge`. It
creates a disposable message with two buttons and a temporary guild slash command.
Click the callback button, click the modal button, submit `jido-ui-proof`, then
run the command printed by the test. It checks exact public input, successful
responses within three seconds, and host-store cleanup. The extra DM delivery
probe reports Discord permission rejection separately from successful OpenDm.
`DISCORD_TEST_USER_ID` can override the verified signed-in test account ID.

See [the operation matrix](discord-operation-matrix.md) for evidence and limits.
Covenant checks 20 active obligations in five components. Production coverage
and obligation coverage are separate gates. Fixed schema fixtures are reviewed
API expectations; no test rewrites them from the implementation.

The worker redacts state, current message, reason details, debug log, and process
dictionary in OTP status/error reports. A controlled raw-frame failure tests
this boundary. The Mint socket process runs with the Erlang sensitive flag,
which limits process inspection and tracing. This does not establish secrecy
for every TLS, VM crash-dump, or host logger failure path. Hosts must protect
those logs.
