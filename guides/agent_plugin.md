# Agent connections and the shared Sensor

`Jido.Chat.Plugin` is in `jido_chat`. It adds a Chat DSL to Jido V3. The SDK
application starts no Plugin or Sensor. The host starts Jido and its Agent.
The AgentServer owns the Plugin supervisor, resolved Clients, and Sensors.

```elixir
defmodule SupportAgent do
  use Jido.Agent, name: "support"

  agent do
    plugin Jido.Chat.Plugin
    schema Zoi.object(%{})
  end

  chat do
    connection :support_telegram do
      client Jido.Chat.Telegram.Adapter,
        id: "support/telegram",
        credentials: %{token: env("TELEGRAM_BOT_TOKEN")}

      rooms [env("TELEGRAM_TEST_CHAT_ID")]
      commands [Jido.Chat.SendMessage]
      source Jido.Chat.Telegram.Source,
        emit: "jido.chat.message.received"
    end
  end

  routes do
    route "jido.chat.message.received", SupportReply,
      emits: ["jido.chat.command.send_message"]
    route "jido.chat.command.*", Jido.Chat.Plugin.Execute, emits: []
    # Add explicit completion and failure routes when results are needed.
  end
end

defmodule SupportReply do
  use Jido.Action, name: "support_reply", schema: Zoi.map()

  def run(params, context) do
    command = Jido.Chat.Signal.SendMessage.new!(%{
      "client_id" => context.chat.client_id,
      "request_id" => params["item_id"] <> ":reply",
      "room_id" => params["room_id"],
      "reply_to_id" => params["message_id"],
      "text" => "Received"
    })

    {:ok, context.agent_state, [Jido.Agent.Directive.emit(command)]}
  end
end
```

Compile `SupportReply` before the Agent in a single file. The host starts it with
`Jido.start_agent/3` and waits with `Jido.AgentServer.await_ready/1`. Readiness
confirms local startup; it does not confirm provider access.

`env/1` and runtime resolution belong to Jido Core. Client credentials are resolved
once at Agent activation. They stay out of Signals. A second connection can use
another adapter and a distinct Client ID. Incoming context selects the reply
Client; no Action needs to select a provider. The host supplies any AI Action or
Flow later through the same routes.

## Independent composition

The Sensor does not call AgentServer. It uses Signal Dispatch:

```elixir
{:ok, sensor} = Jido.Chat.Sensor.start_link(
  client: client,
  source: Jido.Chat.Telegram.Source,
  emit: "jido.chat.**",
  interval: 1_000,
  dispatch: {:pid, target: self()}
)
# Receives {:signal, %Jido.Signal{}}. A Bus Dispatch target also works.
```

The Plugin supplies its own Dispatch adapter for Agent admission. A webhook host
can omit the Sensor and call `Jido.Chat.Plugin.ingest(server, :support_telegram, signal)`
after normalization. Output still uses the same command route and SDK Actions.

A source implements `Jido.Chat.Sensor.Source`. The Plugin always starts the
shared Sensor; no Sensor module appears in the DSL.

A polling source supplies:

```elixir
def mode, do: :poll
def signal_types, do: ["jido.chat.message.received"]
def poll_interval(options), do: Keyword.get(options, :interval, 1_000)
def read(client, cursor, options), do: {:ok, normalized_signals, next_cursor}
```

A push source supplies:

```elixir
def mode, do: :push
def signal_types, do: ["jido.chat.message.received"]
def start_link(client, sensor, options) do
  # Start a linked provider connection worker and return promptly.
  ProviderWorker.start_link(client: client, sensor: sensor, options: options)
end

# In the worker, after provider input has been normalized:
:ok = Jido.Chat.Sensor.push(sensor, delivery.signals)
```

The worker must not call the Sensor synchronously from `start_link/3` or its
initialization. It can receive input after startup. The Sensor stops when its
worker exits. Its host supervisor can then restart the Sensor and source as one
unit. Sensor shutdown stops the linked worker. The worker owns protocol
acknowledgements, heartbeats, and reconnect rules. A protocol acknowledgement is
not a chat reply. The source never runs SendMessage or builds Agent responses.

An optional `key(client, options)` returns an opaque identity to prevent duplicate
provider connections. Never return the credential itself.

Both modes use the same catalog, source, room, emit, Dispatch, and duplicate checks.
A polling cursor advances only after all selected facts are accepted. A push call
returns `:ok` only when the batch is admitted; errors leave unaccepted input for
the provider worker to retry. The last 1,024 accepted identities suppress repeated
input after a partial failure. Restart loses cursor and duplicate memory. There
is no durable delivery guarantee. Provider receipts must not depend on AI or reply
completion; `:ok` confirms input admission only.

Telegram owns its default polling interval of 1,000 milliseconds. An optional
`options: [interval: 2_000]` on the DSL source changes that provider policy. Push
sources start no polling timer.

## Scope and limits

The Plugin accepts facts only from the activated Client source, configured rooms,
and declared Sensor types. Output must use an allowed Action and an allowed room.
Callback commands without a room use a short, Client-scoped room grant from the
admitted interaction. The current grant lasts 30 seconds. This policy needs a
configurable deadline before broader callback use.

Telegram.Source reads messages, edits, reaction changes, and button callbacks.
It uses FetchUpdates and returns five fact types. Other normalized Telegram facts
remain available through the SDK; they are outside this initial polling source.
It never sends replies, adds reactions, or answers callbacks. Domain Actions do
that work through SDK command Signals.

There is no topology wiring or Core overlay patch. Persistent cursors, delivery
queues, retries across restart, and message history remain host or Messaging work.

## Current V3 dependency gate

Jido uses a pinned GitHub commit from the `release/v3` branch. The other
dependencies use public Hex packages. Explicit Hex overrides for Action and
Runic replace the local development paths in Jido's Mix file.

The Jido dependency has `runtime: false`: normal SDK application startup does
not start Jido. A Plugin host must start Jido itself.

The published Jido `3.0.0-beta.1` package lacks the `Jido.Config` API used by
this Plugin. Use the pinned GitHub source until a compatible release is available.

## Input selection and definition checks

`emit` accepts a pattern or a nonempty list. A list selects the union of its
patterns. Each pattern must select at least one type advertised by the Source.
For example:

```elixir
source Jido.Chat.Telegram.Source,
  emit: ["jido.chat.message.*", "jido.chat.reaction.*", "jido.chat.action.received"]
```

Every selected type must have a route. The Plugin reports the connection name
and missing type. Chat routes must not overlap. The check intersects wildcard
patterns, including future types. Its error includes both paths. Use separate
core and provider command namespaces when a middle `**` would overlap a result
route. Routes outside the Chat namespace are not subject to this check.

Connection names are arbitrary atoms. Input context contains
`%{chat: %{connection: name, client_id: id, adapter: adapter}}`. Use the Client ID
to address output. Use adapter identity for explicit provider policy. Credentials
stay in the resolved Client. Missing environment references report the
connection and field path without configuration values.

Activation rejects permitted Actions that the adapter does not support. A
registered command rejected during dispatch also returns a correlated public
failure Signal to the Agent. Scope and permission rejection use code `forbidden`
and outcome `not_attempted`. The original error tuple remains available to a
direct dispatch caller. Unknown, unregistered command types have no result
contract and cannot produce a typed failure. Result dispatch is best effort.

## Local status

`Jido.Chat.Plugin.status(server)` returns status by connection name. For example:

```elixir
%{support_telegram: %{process: :running, provider: :read_succeeded}}
```

A connection without a Source has process status `:disabled`. A running Sensor
starts with provider status `:unknown`. Poll input changes it to `:read_succeeded`
or `:read_failed`. Push input changes it to `:input_observed`. These are the last
observations, not a provider readiness or continuous connection check.
`Jido.Chat.Sensor.status(sensor)` supplies the same observation for a standalone
Sensor. Agent readiness confirms only local startup.

Sensors use one-for-one supervision. One Sensor restart leaves its peers running.
All children share the host supervisor restart budget. No delivery guarantees,
durable storage, or automatic Chat output retries are provided. Use a Signal Bus
or a more resilient host when needed.
