# Provider setup and migration

Jido Chat includes the five adapters below. Add the dependencies for the
transport features your host uses.

| Adapter | Feature | Add to the host's Mix dependencies |
| --- | --- | --- |
| [Telegram](providers/telegram.md) | Bot API and polling | `{:ex_gram, "~> 0.71.0"}`, `{:req, "~> 0.7.1"}` |
| [Discord](providers/discord.md) | REST | `{:req, "~> 0.7.1"}` |
| [Discord](providers/discord.md) | Gateway | REST dependencies plus `{:mint, "~> 1.8"}` and `{:mint_web_socket, "~> 1.0.6"}` |
| [Slack](providers/slack.md) | Web API | `{:req, "~> 0.7.1"}` |
| [Slack](providers/slack.md) | Socket Mode | `{:req, "~> 0.7.1"}`, `{:websockex, "~> 0.5.1"}` |
| [Signal Messenger](providers/signal.md) | JSON-RPC | `{:req, "~> 0.7.1"}` and a running `signal-cli daemon --http` |
| [Signal Messenger](providers/signal.md) | CLI | A host-installed `signal-cli` executable |
| [X](providers/x.md) | Direct Messages | `{:xdk_elixir, "~> 1.0"}` and a host-owned XDK client |

For example, this local host uses the Telegram transport.

```elixir
defp deps do
  [
    {:jido_chat, path: "../jido_chat"},
    {:ex_gram, "~> 0.71.0"},
    {:req, "~> 0.7.1"}
  ]
end
```

Declare transport dependencies directly in the host so their versions have
explicit constraints. Jido's current dependency graph already includes Req,
Mint, and WebSockex. ExGram, Mint WebSocket, and XDK enter the graph when the
host selects them.

Client construction, capability discovery, normalization, and webhook
verification work without provider SDKs. A Client can use an injected transport
with `transport: MyTransport`. If a default transport needs an unavailable
dependency, operations report a typed failure with outcome `not_attempted`.
Direct transport calls return a reason such as
`{:error, {:not_attempted, {:missing_dependency, :ex_gram}}}`.

The host supplies credentials and starts any required input process. Use the
[Agent connection guide](agent_plugin.md) to configure a Sensor, or pass input
from your own HTTP server to `Jido.Chat.normalize/3`.

## Upgrade from a standalone package

1. Point the host's `:jido_chat` dependency to the consolidated source.
2. Remove the corresponding `:jido_chat_telegram`, `:jido_chat_discord`,
   `:jido_chat_slack`, `:jido_chat_signal`, or `:jido_chat_x` dependency in
   the same edit. This gives Mix one owner for the adapter modules.
3. Add the transport dependencies from the table. Run `mix deps.get`.
4. Check outbound operations and the input path with your host's test transport
   or fixtures.

V3 source consumers keep their adapter modules, credentials, configuration,
Actions, and Signals. Users of the released 1.x standalone packages also need
the [V3 public API migration](public_api.md#removed-api-and-host-boundary).
Create a `Jido.Chat.Client` for each provider account and call `Jido.Chat` or
execute typed request Signals.

| Standalone release | Input and transport changes in V3 |
| --- | --- |
| Telegram 1.2.1 | Replace `Extensions` calls and option structs with typed Telegram Actions and Signal data. Use `Jido.Chat.Telegram.Source` for polling or verify and normalize webhook input in the host. |
| Discord 1.1.0 | Replace Nostrum with Req and, for Gateway input, Mint and Mint WebSocket. Start the Gateway with `Jido.Chat.Discord.Source` through a Sensor. |
| Slack 1.1.0 | Replace `listener_child_specs/2` with a Socket Mode Source or a host-owned HTTP webhook. Put bot, app, and signing credentials in the Client when the corresponding feature needs them. |
| Signal Messenger 1.0.0 | Replace the listener and `transform_incoming/1` with `Jido.Chat.Signal.Source` or `Jido.Chat.normalize/3`. Select `Transport.CliClient` explicitly to keep CLI calls. |
| X 1.0.1 | Supply a configured XDK client and Finch pool. The host verifies Account Activity webhooks and sends decoded events to `Jido.Chat.normalize/3`. |

To share a URL in an X Direct Message, put the URL in the text passed to
`Jido.Chat.send_text/3`. The V3 adapter marks `:send_file` unsupported.
