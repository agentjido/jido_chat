# Jido Chat Telegram

Use the Telegram adapter to send Bot API requests and normalize incoming updates.
Add `:ex_gram` and `:req` to use the default transport and polling. See the
[provider setup guide](../providers.md) for dependency versions.

```elixir
client = Jido.Chat.Client.new!(Jido.Chat.Telegram.Adapter,
  id: "support.telegram",
  credentials: %{token: token}
)

{:ok, result_signal} = Jido.Chat.send_text(client, room_id, "Hello")

{:ok, delivery} = Jido.Chat.normalize(client, provider_input)

poll = Jido.Chat.Signal.Policy.new!(Jido.Chat.Telegram.Signal.SendPoll, %{
  "client_id" => client.id,
  "request_id" => "poll:1",
  "room_id" => room_id,
  "question" => "Ship today?",
  "options" => ["Yes", "No"]
})

{:ok, data} =
  Jido.Exec.run(Jido.Chat.Telegram.SendPoll, poll.data, %{client: client, signal: poll})
{:ok, completed} = Jido.Chat.Telegram.SendPoll.reply(poll, data, source: client.source)
```

All Telegram extension Actions use `Jido.ChatAction`. Each has a native request
Signal, a strict result schema, and generated `Completed` and `Failed` Signals.
Run extensions through `Jido.Chat.execute/3`, `Jido.Exec`, Flow, or a Router-selected Instruction.

| Telegram Actions | Purpose |
| --- | --- |
| `SendPoll` | Send a poll |
| `SendPhoto`, `SendDocument`, `SendSticker`, `SendAnimation`, `SendVideoNote` | Upload bytes or use a portable file reference |
| `GetFile`, `GetMe` | Read file metadata or bot identity |
| `AnswerCallbackQuery` | Answer an `ActionReceived` interaction |
| `SendDraft` | Make one explicit draft update |
| `FetchUpdates` | Read one update batch and return normalized Signals plus `next_offset` |
| `SetWebhook`, `GetWebhookInfo`, `DeleteWebhook` | Make one explicit webhook request |

```elixir
Jido.Chat.Telegram.actions()            # 14 extension Actions
Jido.Chat.Telegram.operations()         # request definition / Action pairs
Jido.Chat.Telegram.event_definitions()  # 10 admitted incoming facts
Jido.Chat.Telegram.signal_definitions() # 42 extension definitions
catalog = Jido.Chat.Telegram.catalog()  # 86 core + 42 Telegram definitions

photo = Jido.Chat.Signal.Policy.new!(Jido.Chat.Telegram.Signal.SendPhoto, %{
  "client_id" => client.id,
  "request_id" => "photo:1",
  "room_id" => room_id,
  "source" => %{
    "content_base64" => Base.encode64(File.read!("photo.png")),
    "filename" => "photo.png"
  },
  "caption" => "SDK check"
})

{:ok, uploaded} = Jido.Chat.execute(client, photo)

ref = uploaded.data["result"]["resource_ref"]
# %{"client_id" => client.id, "kind" => "media", "id" => "telegram://file/..."}

{:ok, json} = Jido.Signal.Codec.serialize(uploaded)
{:ok, ^uploaded} = Jido.Signal.Catalog.decode(catalog, json)
```

Upload Signals have a 262,144-byte envelope limit. Use core `Jido.Chat.SendFile`
with a client-scoped local file reference for larger uploads. Do not put tokens
or raw provider structs in a Signal.

```elixir
defmodule ReplyFlow do
  use Jido.Flow, name: "telegram_reply"

  flow do
    step "draft", action: Jido.Chat.Telegram.SendDraft,
      params: input(:draft)

    step "send", action: Jido.Chat.SendMessage,
      params: input(:message), needs: ["draft"]

    output(result("send"))
  end
end

{:ok, completed_data} =
  Jido.Exec.run(ReplyFlow, %{draft: draft_signal.data, message: message_signal.data}, %{client: client})
{:ok, completed} = Jido.Chat.SendMessage.reply(message_signal, completed_data, source: client.source)
```

Use the main functions for common calls:

```elixir
Jido.Chat.send_text(client, room_id, "Hello", format: :plain)
Jido.Chat.stream_text(client, room_id, chunks, format: :markdown)
Jido.Chat.send_file(client, room_id,
  %{"content_base64" => Base.encode64("report"), "filename" => "report.txt"})
Jido.Chat.edit_message(client, room_id, message_id, "Updated")
Jido.Chat.add_reaction(client, room_id, message_id, "👍")
Jido.Chat.remove_reaction(client, room_id, message_id, "👍")
Jido.Chat.delete_message(client, room_id, message_id)
{:ok, downloaded} = Jido.Chat.download_file(client, resource_ref)
bytes = Base.decode64!(downloaded.data["result"]["content_base64"])
{:ok, metadata} = Jido.Chat.fetch_metadata(client, room_id)
{:ok, typing} = Jido.Chat.start_typing(client, room_id)
{:ok, created} = Jido.Chat.create_thread(client, forum_room_id, "Release")
thread_id = created.data["result"]["id"]
Jido.Chat.start_typing(client, forum_room_id, thread_id: thread_id)
Jido.Chat.send_text(client, forum_room_id, "Ready", thread_id: thread_id)
Jido.Chat.capabilities(client)
```

The operation functions return completion Signals from the existing Actions.
Edits accept `format` and `keyboard`; an empty keyboard clears buttons.
Deletes and reactions return `result["acknowledged"]`. Downloads return base64
bytes in the result Signal. Each operation accepts `request_id`, private
`options`, `signal_options`, and an execution `timeout` in milliseconds (default `:infinity`). Capability discovery performs no I/O and uses
canonical keys, including `:send_message` for `send_text`. It reports declared
support; it does not check current bot permissions.

Metadata results contain `id`, `kind`, and optional `name`. Typing sends one notice
and returns an acknowledgement. The host owns any timer that repeats it.
Thread creation creates a named forum topic and returns `id`, `room_id`, and `name`.
The destination must support topics and the bot must have topic permission.

`stream_text` runs the core StreamText Action. Telegram selects draft previews
for positive numeric private chat IDs and persists the complete message when the
source ends. Other destinations use send and edit. The default interval between
intermediate writes is 1000 ms. Final content is always flushed. Markdown previews
repair incomplete syntax; the final send keeps the original text.

Set `config: [stream_delivery: :edit]` on the Client to use edits for private chats.
A call can override it with `options: [stream_delivery: :edit]`. Modes are `:auto`,
`:draft`, and `:edit`. There is no retry or change of mode after a failed write.
An unknown outcome can leave a partial message. The host owns recovery.
The source is consumed once in the Jido.Exec execution task. The adapter adds no
worker, queue, process tree, or stored stream state. A host can also compose the
individual SendDraft and SendMessage Actions directly, as in the Flow above.

`FetchUpdates` accepts `offset`, `limit`, `timeout`, and `allowed_updates`. Its
result contains serialized native Signal envelopes. Decode them with `Jido.Chat.catalog(client)`. The host stores `next_offset` and schedules the next call. A host with
webhook delivery passes each update to `Jido.Chat.normalize/3` instead.

The host supplies credentials and owns listeners, acknowledgements, duplicate
checks, storage, and retries. The adapter does not retain Clients or provider
deliveries. Use `transport: MyTransport` to select a test or host transport.

Binding, resource storage, listener factories, and managed ingress workers are
removed. Low-level provider transports remain available. Normalizer and Membership are internal helpers.

[Covenant contracts](telegram-contracts.md) define the adapter, Telegram Actions,
and Signals. They use fixed fixtures and a recording transport. Run the contract
gate with `mix test.contracts`.

For local development:

```sh
mix deps.get
mix test
mix quality
```

Live tests are excluded by default. Set `TELEGRAM_BOT_TOKEN` and
`TELEGRAM_TEST_CHAT_ID` in the shell environment. Use the shared Telegram suite
to run the public API and native Action cases together.

```sh
JIDO_CHAT_LIVE_PROVIDERS=telegram mix test test/live --include live
```

Use the `test/live` path to select the shared suite. The summary shows the
provider and case ID, with the reason for an inactive, unsupported, or blocked
case. An applicable case with missing setup fails the command. For the manual
callback, use the dedicated test bot and click **Verify Jido SDK** when prompted.

```sh
JIDO_CHAT_LIVE_PROVIDERS=telegram RUN_LIVE_TELEGRAM_UI_TESTS=true \
  mix test test/live --only live_case:A17
```

The older entry points run the same cases in separate groups when the shared
provider selector is empty.

```sh
RUN_LIVE_TELEGRAM_TESTS=true \
  mix test test/jido_chat/providers/telegram/live_integration_test.exs --include live --trace
```

The existing 17-test live suite uses core and Telegram Actions with real provider calls. It
checks replies, reactions, rich messages, the three main functions, both stream delivery paths, draft Flow, file
bytes, media dimensions, Router, Catalog, Dispatch, and Bus. The final test needs
a fresh click on **Verify Jido SDK** in Telegram within three minutes. It answers
that callback through `AnswerCallbackQuery`; an expired callback cannot pass.
Use a test bot with no other polling consumer and no active webhook.
Set `TELEGRAM_CALLBACK_TIMEOUT_MS` to allow more time for the manual button check.

The separate 21-test public API suite calls all eleven operation functions and
`Jido.Chat.capabilities` with the Telegram adapter. It checks request and trace context,
Markdown and HTML, replies and keyboards, lazy streams, draft and edit delivery,
inline and local uploads, reuse of file references, exact document downloads,
normalization, edits and keyboard removal, deletion, reactions, room metadata,
typing notices, topic creation and delivery to the returned thread ID, capability
discovery, input validation, and real provider rejections. Downloads use
`Jido.Chat.download_file`; cleanup uses `Jido.Chat.delete_message`.
It also checks `Jido.Chat.execute` with one real FetchUpdates request. It does not call Actions directly.
Its transport observer forwards every request to the real Telegram transport.

```sh
RUN_LIVE_TELEGRAM_TESTS=true \
  mix test test/jido_chat/providers/telegram/public_api_live_test.exs --include live --trace
```

This suite needs no manual click and does not change webhooks. It reads one
update batch without an offset and compares its normalized facts with the shared
normalizer. It does not advance the update queue. Its two
draft tests need a positive private chat ID. Other chat IDs block those tests.
Messages are deleted after each test by default. Set
`TELEGRAM_PUBLIC_API_KEEP_MESSAGES=true` to keep them for Desktop inspection.
The output shows a run ID that also appears in the messages.

Set `TELEGRAM_TEST_FORUM_CHAT_ID` to a forum supergroup for the public API suite's
successful topic creation test. Without it, the suite reports that case as blocked. A separate test
checks rejection of an invalid destination. The bot needs topic rights. Created
test topics remain in the forum; messages are deleted by default.
The existing Action suite checks rejection in the default chat when no forum
chat is configured, or successful topic creation when a forum chat is configured.
Fixtures are local; the suite does not use external fixture URLs.

To leave a visible Action and Flow proof in Desktop:

```sh
MIX_ENV=test RUN_LIVE_TELEGRAM_TESTS=true \
  mix run examples/providers/telegram/live_proof.exs
```

Managed bridge bindings belong in Jido Chat Runtime. The legacy Ingress,
Extensions, FileInfo, MediaMessage, option structs, and keyboard structs are removed.
The adapter exposes only native callbacks. Use Actions for provider operations.
GetFile and DownloadFile share one validated file resolver. SendFile and provider
media Actions share the same source schema and upload implementation.

```elixir
# Content belongs in the request Signal, including buttons:
"keyboard" => %{"rows" => [[%{"text" => "Confirm", "value" => "confirm:1"}]]}
# Remove buttons with an EditMessage request:
"keyboard" => %{"rows" => []}
```

Put a webhook secret in `Client.credentials.secret_token`. SetWebhook sends it
privately. `Jido.Chat.Telegram.Webhook.verify(client, headers)` checks that secret
without I/O. The host owns HTTP responses, polling loops, offsets, and retries.

The shared Action, Flow, Router, and Dispatch proof is in the core package at
`integration/stateless`. See the core `guides/static_sdk.md` for the full API.

All core Actions now have their own Completed and Failed Signals, matching the
Telegram extension convention. Result operation fields contain the full request
type. Telegram supports 12 core Actions, including CreateThread with room_id and
name, and DownloadFile with resource_ref. Old OpenThread, FetchMedia, Stream,
and generic OperationCompleted/OperationFailed APIs are removed.

Configured discovery uses `Jido.Chat.actions(client)`, `operations(client)`,
`signal_definitions(client)`, `event_definitions(client)`, and `catalog(client)`.
Telegram adds 14 Actions to the 23 core Actions. Its configured catalog contains
128 Signal definitions. The old `command_routes/0` is removed. `GetWebhookInfo`
uses the query type `jido.chat.telegram.query.get_webhook_info`.

Action JSON schemas match the request and completion data schemas. Pass request
data to Exec. A request Signal can be supplied as `context.signal` to keep its
identity and trace. Use `reply/3` to build a completion Signal. Decode serialized
Signals with the Catalog before execution. Secrets and streaming sources stay
in private context. Failures retain only safe codes,
outcomes, and optional `retry_after_ms`; raw Telegram errors are not exposed.
A partial stream failure or execution deadline has an unknown provider outcome.

`OpenDm` verifies an existing private destination with `getChat`. It does not
create access to a user who has not opened a bot conversation. Incoming forum
service updates produce `ThreadStarted` and `ThreadChanged` facts. FetchUpdates
and webhook normalization use the same path; the host owns repeated reads and
offset storage. FetchMessages remains unsupported for Telegram chat history.

## Receive-only source

`Jido.Chat.Telegram.Source` implements `Jido.Chat.Sensor.Source`. Use it with
`Jido.Chat.Sensor` in `Jido.Chat.Plugin`, or supply a Signal Dispatch target
directly. It reads messages, edits, reactions, and button callbacks through
`FetchUpdates`. It does not send replies or answer callbacks. See
`guides/agent_plugin.md` in Jido Chat core.

The Agent declaration needs only the provider source and its Signal pattern:

```elixir
source Jido.Chat.Telegram.Source, emit: "jido.chat.message.received"
```

The Plugin starts the shared Sensor. `Telegram.Source.mode/0` returns `:poll`.
The source owns the 1,000 ms polling default. Optional source
`options: [interval: 2_000]` changes this delay.
