# Jido Chat Slack

Add `:req` for the default Web API transport. Add `:websockex` for the
default Socket Mode Source. See the [provider setup guide](../providers.md)
for dependency versions.


The adapter is stateless. A `Jido.Chat.Client` holds private credentials and
transport settings. Client construction starts no process and makes no request.

```elixir
client =
  Jido.Chat.Client.new!(Jido.Chat.Slack.Adapter,
    id: "slack/support",
    credentials: %{
      bot_token: System.fetch_env!("SLACK_BOT_TOKEN"),
      app_token: System.fetch_env!("SLACK_APP_TOKEN"),
      signing_secret: System.fetch_env!("SLACK_SIGNING_SECRET")
    },
    config: [bot_user_id: System.get_env("SLACK_BOT_USER_ID")]
  )

{:ok, completed} = Jido.Chat.send_text(client, "C123", "Hello from Jido")
message_id = completed.data["result"]["id"]
```

The bot token is required only for Web API operations. The app token is required
only for Socket Mode. The signing secret is required only for webhook checks.
Credentials never enter request, result, or incoming fact Signals.

## Agent connection

Use `Jido.Chat.Plugin` in the Agent and add the Slack connection to its `chat`
block. Environment references are resolved when the Agent starts.

```elixir
connection :slack do
  client Jido.Chat.Slack.Adapter,
    id: "slack/support",
    credentials: %{
      bot_token: env("SLACK_BOT_TOKEN"),
      app_token: env("SLACK_APP_TOKEN"),
      signing_secret: env("SLACK_SIGNING_SECRET")
    },
    config: [bot_user_id: env("SLACK_BOT_USER_ID")]

  rooms [env("SLACK_CHANNEL_ID")]
  commands [Jido.Chat.SendMessage]
  source Jido.Chat.Slack.Source, emit: "jido.chat.**"
end
```

Jido Chat core owns the Sensor, Agent integration, room runtime, storage, and
durable declarations. This package owns only Slack protocol behavior.

## Socket Mode

For a host without the Agent Plugin, start the shared Sensor directly:

```elixir
{:ok, sensor} =
  Jido.Chat.Sensor.start_link(
    client: client,
    source: Jido.Chat.Slack.Source,
    emit: "jido.chat.**",
    rooms: ["C123"],
    dispatch: {:pid, target: self()}
  )
```

The Source starts one linked Socket Mode worker. The worker opens the connection,
normalizes the inner payload, asks the Sensor to admit its facts, and then sends
the Slack envelope acknowledgement. Rejected input is not acknowledged. The
worker reconnects with bounded backoff. It does not store chat history or send a
chat reply.

## Webhooks

The host owns the HTTP server and response deadline. Verify the exact request
body before decoding it:

```elixir
with :ok <- Jido.Chat.Slack.Webhook.verify(client, raw_body, request_headers),
     {:ok, payload} <- Jido.Chat.Slack.Webhook.decode(raw_body, request_headers),
     {:ok, delivery} <- Jido.Chat.normalize(client, payload) do
  MyApp.accept(delivery.signals)
end
```

`Jido.Chat.Slack.Webhook.response/2` can build a plain HTTP interaction response.
It starts no process and performs no I/O.

## Supported operations

Slack uses native implementations for messages, finite text streams, files,
edits, deletes, metadata, thread and message reads, users, subjects, participants,
read receipts, downloads, reactions, ephemeral messages, modals, dynamic options,
message history, thread lists, and direct rooms. `Jido.Chat.capabilities/1`
returns the exact matrix.

Slack history reads support backward pagination. Incoming Events API,
interactivity, modal, options, and slash command payloads normalize to public
Jido Chat fact Signals. Raw Slack payloads and credentials are not copied into
those Signals.

## Validation

Default checks do not call Slack:

```sh
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix test.contracts
mix quality
mix coveralls
```

The optional live test requires `SLACK_BOT_TOKEN` and `SLACK_TEST_CHANNEL_ID`:

```sh
mix test test/jido_chat/providers/slack/live_integration_test.exs --include live
```

`Jido.Chat.Slack.Renderer` converts cards, modals, and options to Slack Block
Kit values. The adapter takes credentials from the Client. Tests cover Web API
request and error shapes, event normalization, signature verification, Block
Kit rendering, and Socket Mode admission before acknowledgement.
