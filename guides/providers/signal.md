# Jido Chat Signal

Use the Signal Messenger adapter with `signal-cli`. Add `:req` for the
default JSON-RPC transport, or select the CLI transport to call your local
executable directly. See the [provider setup guide](../providers.md).

## Client and operations

Create an immutable client. Store the Signal account identity in
`credentials`. Store endpoint, executable, and transport policy in `config`.

```elixir
client = Jido.Chat.Client.new!(Jido.Chat.Signal.Adapter,
  id: "support-signal",
  credentials: %{account: System.get_env("SIGNAL_ACCOUNT")},
  config: [
    endpoint: System.get_env("SIGNAL_RPC_ENDPOINT"),
    executable: System.get_env("SIGNAL_CLI_PATH") || "signal-cli"
  ]
)

{:ok, result} = Jido.Chat.send_text(client, "+15555550100", "Hello from Jido")
message_id = result.data["result"]["id"]
```

The current native operations are `send_message` and `send_file`. All other
core operations are explicitly unsupported and stop before provider I/O.

## Inbound polling

Start the Signal daemon in manual receive mode for JSON-RPC polling.

```sh
signal-cli -a +15555550100 daemon --http=127.0.0.1:8080 --receive-mode manual --no-receive-stdout
```

`Jido.Chat.Signal.Source` is a receive-only polling Source for the shared Jido
Chat Sensor. It supports both the CLI and JSON-RPC transports. The Source passes
the account as a distinct private argument and passes only client config and
polling policy in the option list.

The Source normalizes complete receive batches into ordered
`MessageReceived` and `NormalizationFailed` Signals. Its key includes the
transport, account, endpoint, executable, and CLI config path so separate
provider identities do not share a polling process.

Jido Chat core owns the managed Sensor, Rooms, provider declarations, bridges,
storage, and application Signal Bus. This package starts no managed process
tree by itself.

## Transport choices

- `Jido.Chat.Signal.Transport.JsonRpcClient` uses a `signal-cli daemon --http`
  endpoint.
- `Jido.Chat.Signal.Transport.CliClient` runs one local `signal-cli` command
  for each send or receive request.

Signal does not provide an official bot API. Protect account files and local
daemon endpoints. Do not put account identity or raw provider data in Signal
payloads or logs.

## Checks

Run `mix test`, `mix test.contracts`, and `mix quality`. Live tests stay tagged
`:live` and excluded by default. They run only when `RUN_LIVE_SIGNAL_TESTS` and
the required local signal-cli values are set.

Run the live check with:

```sh
RUN_LIVE_SIGNAL_TESTS=true mix test test/jido_chat/providers/signal/live_integration_test.exs --include live
```
