# Jido Chat X

The X adapter handles Direct Messages. Add `:xdk_elixir` for the default
transport. See the [provider setup guide](../providers.md) for the
dependency version.

## Client setup

Provider resources stay in the local immutable Client value. They do not enter
request, result, or inbound Signals.

```elixir
client =
  Jido.Chat.Client.new!(Jido.Chat.X.Adapter,
    id: "support-x",
    config: [xdk_client: my_xdk_client]
  )
```

The host owns X authentication and the `Xdk` client lifecycle. Add
`Xdk.child_spec(name: MyApp.XFinch)` to the host supervisor and build the
client with `Xdk.new(finch: MyApp.XFinch, auth: auth)`. Supply the resulting
client as `:xdk_client` in private transport options.

## Typed operations

Use Jido Chat operations with the configured Client:

```elixir
{:ok, sent} = Jido.Chat.send_text(client, x_user_id, "Hello")

{:ok, page} =
  Jido.Chat.Signal.Policy.new!(Jido.Chat.Signal.FetchMessages, %{
    "client_id" => client.id,
    "request_id" => "history-1",
    "room_id" => "conversation:12345"
  })
  |> then(&Jido.Chat.execute(client, &1))
```

The adapter supports these native operations:

- `send_message`
- `delete_message`
- `fetch_message`
- `fetch_messages`
- `open_dm`

All other core operations return a typed `not_attempted` result without
provider I/O.

## Inbound delivery

For Account Activity webhooks, configure a host endpoint and subscribe the
authenticated X account. Answer CRC GET checks with the HMAC-SHA256
`response_token`. Verify POST request bodies with
`x-twitter-webhooks-signature` before decoding. Acknowledge the input in the
host and normalize each verified payload.

```elixir
{:ok, delivery} = Jido.Chat.normalize(client, verified_x_payload)

Enum.each(delivery.signals, fn signal ->
  # Apply the fact through the host-owned Jido Chat runtime or application flow.
end)
```

Normalization is deterministic. It keeps provider item order, gives each item
a stable identity, and turns unsupported provider items into explicit
normalization-failure facts.

## Runtime ownership

Jido Chat core owns the optional managed Room and provider runtime. This
adapter owns only X request mapping, response mapping, and input normalization.
It does not start a listener, room process, persistence process, or second
messaging tree.

## Offline checks

```bash
mix test
mix test.contracts
mix quality
mix docs -f html -f markdown
```

Normal tests use fixed transports and make no X request. Live tests are tagged
and excluded by default.

## Live checks

The shared live suite registers all 38 baseline cases and reports unsupported
cases. Set the four OAuth 1.0 values in `.env.example` for A02, the read-only
XDK identity check.

```bash
JIDO_CHAT_LIVE_PROVIDERS=x mix test test/live/x_test.exs --only live_baseline
```

To enable DM writes, set `RUN_LIVE_X_SEND_TESTS=true` and
`X_TEST_RECIPIENT_ID` to a dedicated numeric test user ID. P01 and A07 leave
their test DMs in the conversation. P13 and A01 send a test DM, read it back,
and delete it only after checking the event ID, conversation ID, sender,
and exact text. A failed ownership check leaves the DM in place.

P21 requires a host-owned Account Activity webhook and a fresh test message
from a separate sender. The shared suite has no live webhook fixture for X.

## Documentation

Run `mix docs -f html -f markdown`. The command creates HTML documentation and
`doc/llms.txt`.
