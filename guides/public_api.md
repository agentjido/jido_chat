# Current public API

Current `3.0.0-dev` source, 2026-10-18. This is a breaking API change.
Covenant contracts enforce this boundary; see [the contract guide](contracts.md).

The core has **23 Actions and 86 Signal definitions**: 23 requests, 46 Action
results, and 17 incoming facts. Telegram adds **14 Actions and 42 definitions**.
The combined Telegram catalog has **128 definitions**.

## Main functions

```elixir
{:ok, sent} = Jido.Chat.send_text(client, room_id, "Hello", format: :plain)

{:ok, streamed} = Jido.Chat.stream_text(client, room_id,
  ["**Hello", " world**"], format: :markdown)

{:ok, uploaded} = Jido.Chat.send_file(client, room_id,
  %{"content_base64" => Base.encode64("report"), "filename" => "report.txt"},
  caption: "Report", media_kind: :file)

message_id = sent.data["result"]["id"]
{:ok, edited} = Jido.Chat.edit_message(client, room_id, message_id, "Updated")
{:ok, added} = Jido.Chat.add_reaction(client, room_id, message_id, "👍")
{:ok, removed} = Jido.Chat.remove_reaction(client, room_id, message_id, "👍")
{:ok, deleted} = Jido.Chat.delete_message(client, room_id, message_id)

ref = hd(uploaded.data["result"]["media"])["resource_ref"]
{:ok, downloaded} = Jido.Chat.download_file(client, ref)
bytes = Base.decode64!(downloaded.data["result"]["content_base64"])

{:ok, metadata} = Jido.Chat.fetch_metadata(client, room_id)
metadata.data["result"] # %{"id" => room_id, "kind" => "group", "name" => "Support"}
{:ok, typing} = Jido.Chat.start_typing(client, room_id)

{:ok, created} = Jido.Chat.create_thread(client, forum_room_id, "Release")
thread_id = created.data["result"]["id"]
{:ok, typing} = Jido.Chat.start_typing(client, forum_room_id, thread_id: thread_id)
{:ok, sent} = Jido.Chat.send_text(client, forum_room_id, "Ready", thread_id: thread_id)

capabilities = Jido.Chat.capabilities(client)
capabilities[:send_message] # :native or :unsupported; covers send_text
capabilities[:edit_message]
```

The eleven operation functions execute the existing Actions with request Signals.
They return `{:ok, completed_signal}` or an error. Each operation generates a
request ID unless `request_id:` is supplied. IDs correlate calls; they do not
deduplicate. Edits return a message result with status `updated`. Deletes and
reactions return `result["acknowledged"]`. Downloads return base64 bytes in the
completion Signal; they do not write a local file.

Metadata results contain `id`, `kind`, and optional `name`. Typing sends one notice
and returns `result["acknowledged"]`. The host owns any timer that repeats the call.
Thread creation returns `id`, `room_id`, and `name`. The host can pass that ID to
the text and typing functions. Telegram creates a named forum topic; the room
must support topics and the bot must have permission to create them.

Every operation accepts `request_id`, `options: [...]` for private transport
options, `signal_options: [...]` for Signal constructor metadata, and `timeout:`
for the execution deadline. The deadline is a non-negative number of milliseconds
or `:infinity` (the default). Unknown or duplicate options fail.

Text sends, streams, and files also accept `format` (`:plain`, `:markdown`, `:html`,
or strings), `thread_id`, `reply_to_id`, and `keyboard`. Files accept `caption`
and `media_kind` (`:file`, `:image`, or strings). Streams accept `update_interval_ms`
(a non-negative integer). Edits accept `format` and `keyboard`; they cannot change
the room, thread, or parent. Use `keyboard: %{"rows" => []}` to clear buttons.
Typing accepts `thread_id`. Deletes, downloads, reactions, room metadata, and thread
creation accept only the shared metadata and private options.

`capabilities/1` returns a map directly. It reads the adapter's declaration with
no I/O or Action execution. Keys are the canonical operation names, including
`:send_message` for `send_text`. Every core operation has status `:native` or
`:unsupported`. This is declared support, not a check of current bot permissions
or provider availability. The host can use it to select available agent Actions.

The lazy stream source stays in private Action context at `options[:stream]`.
It can come from `ReqLLM.StreamResponse.tokens(response)` or any Enumerable of
text chunks. It is read once in the Jido.Exec execution task. No stream worker,
registry, queue, or retained state is added. The call completes after the final
message is written. A serialized command does not contain a replayable source.
The host must supply the source again if it chooses to execute the command again.

## Client and execution

```elixir
client = Jido.Chat.Client.new!(Jido.Chat.Telegram.Adapter,
  id: "support.telegram",
  credentials: %{token: telegram_token}
)

request = Jido.Chat.Signal.SendMessage.new!(%{
  "client_id" => client.id,
  "request_id" => "announcement:1",
  "room_id" => "12345",
  "text" => "Hello"
})

{:ok, %{signal: completed}} =
  Jido.Exec.run(Jido.Chat.SendMessage, %{signal: request},
    %{client: client}, max_attempts: 1)

completed.type == Jido.Chat.SendMessage.Completed.type()
# "jido.chat.command.send_message.completed"
completed.data["operation"] == request.type
completed.data["result"]["id"] # actual provider message ID

# Core convenience entry points:
{:ok, completed} = Jido.Chat.execute(client, request)
{:ok, completed} = Jido.Chat.send_message(client, %{
  "request_id" => "announcement:2", "room_id" => "12345", "text" => "Hello"
})
```

The examples show separate execution paths. Repeating a request can repeat a
provider write. `request_id` provides correlation, not deduplication.

`Client.new/2` returns `{:ok, client} | {:error, error}`. `new!/2` raises on invalid
configuration. The Client captures `id`, `credentials`, optional private keyword
`config`, and optional `transport`. Its `source` is derived from its ID. Construction
performs no I/O and starts no process. `Client.options/1` returns private options.
Never put a Client or credentials in a Signal.

Actions accept `%{signal: request}` and return `{:ok, %{signal: completed}}`.
Private context is `%{client: client, options: keyword_options}`; options are optional.
The convenience functions return `{:ok, completed}` instead. `execute/3` accepts
only `options: private_keyword_options` and `timeout: milliseconds_or_infinity`.
The lower-level `send_message/3` uses these same execution options and requires
`request_id` in its data map. The eleven main helpers generate that ID when omitted.

`Action.to_json/0` exposes complete request and result envelope schemas, including
the exact request data fields, Signal type, and schema identity. Agent input can
contain a serialized envelope at `%{"signal" => envelope}`. The Action decodes and
validates it against its own definition before I/O. Native Exec and Flow calls
can continue to use `%{signal: %Jido.Signal{}}`. Clients, transport options, and
stream sources remain private context.

Every Action has its own `Completed` and `Failed` definitions. Result data contains
`client_id`, `request_id`, and `operation` (the full request Signal type).
A completion also has `result`. An execution failure returns
`{:error, %Jido.Chat.Error{signal: failed}}`. Failure data has `code` and `outcome`:
`not_attempted`, `rejected`, or `unknown`. An unknown outcome can include a provider
write. Request construction and validation can fail before a failure Signal exists.
Trace context and causation link the result to the request.

Failure codes are `unsupported`, `provider_failure`, `invalid_provider_result`,
`unauthorized`, `forbidden`, `not_found`, `rate_limited`, and `timeout`.
A failure can include a safe non-negative `retry_after_ms`. Raw provider errors
and credentials are not included. Convenience-call deadlines return a typed
`timeout` failure with an `unknown` outcome. Native Exec or Flow callers control
their own outer execution deadline. No call automatically retries. A stream
failure has an `unknown` outcome because earlier chunks can already be visible.

## Core Actions

Each row defines `Jido.Chat.<Name>`, `Jido.Chat.Signal.<Name>`,
`Jido.Chat.<Name>.Completed`, and `Jido.Chat.<Name>.Failed`.
Every request requires string-key `client_id` and `request_id` fields in addition
to the fields below. Unknown fields are rejected. Telegram supports 12 core Actions.

| Name | Kind | Required fields | Optional fields | Telegram |
| --- | --- | --- | --- | --- |
| `AddReaction` | command | `message_id`, `reaction`, `room_id` | — | Native |
| `CreateThread` | command | `name`, `room_id` | — | Native |
| `DeleteMessage` | command | `message_id`, `room_id` | — | Native |
| `DownloadFile` | query | `resource_ref` | — | Native |
| `EditMessage` | command | `message_id`, `room_id`, `text` | `format`, `keyboard` | Native |
| `FetchMessage` | query | `message_id`, `room_id` | — | Unsupported |
| `FetchMessages` | query | `room_id` | `cursor`, `direction`, `limit`, `thread_id` | Unsupported |
| `FetchMetadata` | query | `room_id` | — | Native |
| `FetchSubject` | query | `room_id` | `thread_id` | Unsupported |
| `FetchThread` | query | `room_id`, `thread_id` | — | Unsupported |
| `GetThreadParticipants` | query | `room_id`, `thread_id` | — | Unsupported |
| `GetUser` | query | `user_id` | — | Unsupported |
| `ListThreads` | query | `room_id` | `cursor`, `direction`, `limit` | Unsupported |
| `LoadOptions` | query | `interaction_id`, `query` | `action_id`, `limit`, `room_id`, `user_id`, `view_id` | Unsupported |
| `MarkAsRead` | command | `message_id`, `room_id` | — | Unsupported |
| `OpenDm` | command | `user_id` | — | Native |
| `OpenModal` | command | `modal`, `room_id` | — | Unsupported |
| `PostEphemeral` | command | `room_id`, `text`, `user_id` | `format`, `thread_id` | Unsupported |
| `RemoveReaction` | command | `message_id`, `reaction`, `room_id` | — | Native |
| `SendFile` | command | `room_id`, `source` | `caption`, `format`, `keyboard`, `media_kind`, `reply_to_id`, `thread_id` | Native |
| `SendMessage` | command | `room_id`, `text` | `format`, `keyboard`, `reply_to_id`, `thread_id` | Native |
| `StartTyping` | command | `room_id` | `thread_id` | Native |
| `StreamText` | command | `room_id` | `format`, `keyboard`, `reply_to_id`, `thread_id`, `update_interval_ms` | Native |

Use `Action.result_schema/0` for the exact result shape and
`Action.signal_definition().schema/0` for the exact request schema.
Every Action supplies native Jido Action functions (`run/2`, parameter and output
validation, `schema/0`, `output_schema/0`, and `to_json/0`) plus
`signal_definition/0`, `signal_definitions/0`, `result_schema/0`, and the provider
callback `invoke/3`. Normal execution uses `Jido.Exec.run`.

`CreateThread` creates a named thread or topic. It does not require a message ID.
Use the returned thread ID in `SendMessage.thread_id` to send into that thread.
`FetchThread` and `GetThreadParticipants` require an existing `thread_id`.
`EditMessage` changes an existing message; it does not move or reparent it.
An unsupported operation fails before provider I/O. Telegram `OpenDm` reads
`getChat` and requires an existing private chat with the requested user ID. It
returns that destination; it does not establish new bot access to a user.

```elixir
Jido.Chat.actions()            # 23 Action modules
Jido.Chat.operations()         # [{request_definition, action}, ...]
Jido.Chat.signal_definitions() # 86 definitions
Jido.Chat.catalog()            # native Jido.Signal.Catalog
Jido.Chat.event_definitions()  # 17 core incoming facts

Jido.Chat.actions(client)            # core + provider Actions; 37 for Telegram
Jido.Chat.operations(client)         # [{request_definition, action}, ...]
Jido.Chat.signal_definitions(client) # 128 definitions for Telegram
Jido.Chat.event_definitions(client)  # 10 admitted incoming facts for Telegram
Jido.Chat.catalog(client)            # configured native catalog

{:ok, json} = Jido.Signal.Serialization.serialize(completed)
{:ok, decoded} = Jido.Signal.Catalog.decode(Jido.Chat.catalog(), json)
```

All request and result definitions provide `type/0`, `dataschema/0`, `schema/0`,
`default_source/0`, `datacontenttype/0`, `validate_data/1`, and `new/0,1,2` /
`new!/0,1,2`. A result type appends `.completed` or `.failed` to its request type.
Its schema URN appends `:completed` or `:failed` to the request schema URN.

## Incoming events and normalization

The 17 event modules have prefix `Jido.Chat.Signal.`:

```elixir
MessageReceived, MessageUpdated, MessageDeleted,
ReactionAdded, ReactionRemoved, ActionReceived,
ModalSubmitted, ModalClosed, OptionsRequested, SlashCommandReceived,
AssistantThreadStarted, AssistantContextChanged, MembershipChanged,
ThreadStarted, ThreadChanged, ReceiptReceived, NormalizationFailed
```

```elixir
{:ok, delivery} = Jido.Chat.normalize(client, provider_input)
delivery.id      # stable provider delivery identity
delivery.signals # ordered native Signals

Jido.Chat.Delivery.new(client, delivery_id, signals)
Jido.Chat.Delivery.validate(client, delivery)
```

Normalization validates the whole delivery. It does not acknowledge input,
publish Signals, retain history, or check for repeated deliveries. Only facts
declared by `event_definitions(client)` are admitted. An adapter can declare
provider facts with `use Jido.Chat.Signal.Definition` and return them in a Delivery.
They must pass the same JSON, identity, context, and size checks as core facts.
Use the configured catalog to decode them.

Telegram admits `MessageReceived`, `MessageUpdated`, `ReactionAdded`,
`ReactionRemoved`, `ActionReceived`, `MembershipChanged`, `SlashCommandReceived`,
`NormalizationFailed`, `ThreadStarted`, and `ThreadChanged`. Forum service updates
produce the thread facts. Polling and webhook input use the same normalizer.

## Telegram extension Actions

All names have prefix `Jido.Chat.Telegram.`. Request definitions use prefix
`Jido.Chat.Telegram.Signal.`. Results use `<Action>.Completed` and `<Action>.Failed`,
exactly as core Actions do.

| Actions | Purpose |
| --- | --- |
| `SendPhoto`, `SendDocument`, `SendSticker`, `SendAnimation`, `SendVideoNote` | Provider media sends using the shared `source` schema |
| `SendPoll` | Poll with question and options |
| `GetFile` | Validated file metadata for `resource_ref` |
| `GetMe` | Bot identity |
| `AnswerCallbackQuery` | Answer an `ActionReceived` event |
| `SendDraft` | One draft update |
| `FetchUpdates` | One update batch; returns Signal envelopes and `next_offset` |
| `SetWebhook`, `GetWebhookInfo`, `DeleteWebhook` | Explicit webhook operations |

```elixir
Jido.Chat.Telegram.adapter()
Jido.Chat.Telegram.actions()            # 14 Actions
Jido.Chat.Telegram.operations()         # [{request_definition, action}, ...]
Jido.Chat.Telegram.event_definitions()  # 10 admitted incoming facts
Jido.Chat.Telegram.signal_definitions() # 42 definitions
Jido.Chat.Telegram.catalog()            # 128 core + Telegram definitions
Jido.Chat.Telegram.Webhook.verify(client, headers)
```

Run extensions through `Jido.Chat.execute/3`, native Exec, Flow, or an Instruction.
`execute/3` selects from the configured core and provider operation pairs. The host
uses these same pairs to build permitted Router routes. `GetWebhookInfo` is a
query with type `jido.chat.telegram.query.get_webhook_info`. The host supplies its
HTTP response after webhook verification. Put the webhook secret in
`client.credentials.secret_token`.

### Pulling incoming messages

```elixir
pull = Jido.Chat.Telegram.Signal.FetchUpdates.new!(%{
  "client_id" => client.id,
  "request_id" => "pull:1",
  "limit" => 100,
  "timeout" => 20
  # "offset" => stored_offset  # host-owned acknowledgement position
})

{:ok, pulled} = Jido.Chat.execute(client, pull, timeout: 30_000)
result = pulled.data["result"]

signals = Enum.map(result["signals"], fn envelope ->
  {:ok, signal} = Jido.Signal.Catalog.decode(Jido.Chat.catalog(client), envelope)
  signal
end)

next_offset = result["next_offset"]
# The host processes the Signals, stores the offset, and schedules the next call.
```

`FetchUpdates` reads one Telegram batch and uses `Jido.Chat.normalize/3`. Webhook
input produces the same facts. The host owns repeated calls, acknowledgement,
deduplication, and publication. Passing an offset affects Telegram's update queue;
choose when to advance it after processing. This API reads new updates. Telegram
does not support the core `FetchMessages` history query.
The request's `timeout` is Telegram's long-poll duration in seconds; execution
`timeout:` is a deadline in milliseconds.

## Actions, Flow, Router, and Dispatch

```elixir
poll = Jido.Chat.Telegram.Signal.SendPoll.new!(%{
  "client_id" => client.id, "request_id" => "poll:1", "room_id" => "12345",
  "question" => "Release today?", "options" => ["Yes", "No"]
})

defmodule MyApp.AnnouncePoll do
  use Jido.Flow, name: "announce_poll"

  flow do
    step "announce", action: Jido.Chat.SendMessage,
      params: %{signal: input(:announcement)}
    step "poll", action: Jido.Chat.Telegram.SendPoll,
      params: %{signal: input(:poll)}, needs: ["announce"]
    output %{
      announcement: result("announce", [:signal]),
      poll: result("poll", [:signal])
    }
  end
end

{:ok, %{announcement: sent, poll: opened}} =
  Jido.Exec.run(MyApp.AnnouncePoll,
    %{announcement: request, poll: poll}, %{client: client}, max_attempts: 1)

router = Jido.Signal.Router.new!([
  {Jido.Chat.Signal.SendMessage,
   Jido.Instruction.template(:action, Jido.Chat.SendMessage)},
  {Jido.Chat.Telegram.Signal.SendPoll,
   Jido.Instruction.template(:action, Jido.Chat.Telegram.SendPoll)}
])
{:ok, [template]} = Jido.Signal.Router.route(router, poll)
{:ok, instruction} = Jido.Instruction.bind(template, %{signal: poll}, %{client: client})
{:ok, %{signal: opened}} = Jido.Exec.run(instruction)
:ok = Jido.Signal.Dispatch.dispatch(opened, {:pid, [target: self()]})
```

These are separate execution examples. Flow ordering does not undo prior provider
writes. Router selects an Instruction; Exec runs it. Dispatch sends the result.
The host starts and supervises any Jido Signal Bus and chooses when to publish.

## Files and keyboards

```elixir
source = %{"content_base64" => Base.encode64("report bytes"), "filename" => "report.txt"}
# Other sources:
source = %{"client_id" => client.id, "kind" => "file", "id" => "/tmp/report.txt"}
# kind "url": HTTP URL; kind "media": provider file reference.

upload = Jido.Chat.Signal.SendFile.new!(%{
  "client_id" => client.id, "request_id" => "upload:1", "room_id" => "12345",
  "source" => source, "caption" => "Report", "media_kind" => "file"
})
{:ok, %{signal: sent}} = Jido.Exec.run(Jido.Chat.SendFile, %{signal: upload}, %{client: client})
ref = hd(sent.data["result"]["media"])["resource_ref"]

download = Jido.Chat.Signal.DownloadFile.new!(%{
  "client_id" => client.id, "request_id" => "download:1", "resource_ref" => ref
})
{:ok, %{signal: fetched}} = Jido.Exec.run(Jido.Chat.DownloadFile, %{signal: download}, %{client: client})
bytes = Base.decode64!(fetched.data["result"]["content_base64"])
```

Telegram `GetFile` reads metadata. Core `DownloadFile` resolves metadata and reads
the bytes. They use the same validated resolver. Results contain no token URL or
raw provider struct. Upload results require real provider message and file IDs.
Inline content and download results must fit the Signal envelope limit of 262,144
encoded bytes. The host chooses a transfer policy for larger files.

```elixir
keyboard = %{"rows" => [[
  %{"text" => "Confirm", "value" => "confirm:42"},
  %{"text" => "Help", "url" => "https://example.com/help"}
]]}
```

`SendMessage`, `EditMessage`, `SendFile`, and Telegram media/poll requests accept
`keyboard`. Each button has `text` and exactly one of `value` or `url`.
Callback values have a 64-byte limit. Rows have at most eight buttons; a keyboard
has at most 100 buttons. Use `%{"rows" => []}` on an edit to clear the keyboard.
Provider keyboard structs are created only at the transport boundary.

Finite chunk rendering is a pure operation followed by an explicit send:

```elixir
text = Jido.Chat.Markdown.StreamRenderer.render(["Hello ", "world"])
{:ok, completed} = Jido.Chat.send_message(client, %{
  "request_id" => "rendered:1", "room_id" => "12345", "text" => text
})
```

For incremental delivery, use `Jido.Chat.stream_text/4`. The adapter selects its
method inside `invoke/3` when it declares `stream_text: :native`.

Telegram selects drafts for positive numeric private chat IDs. It uses
`sendMessageDraft` or `sendRichMessageDraft`, then persists the exact final content
with `SendMessage`. Other destinations use one `SendMessage`, then `EditMessage`
updates to that message. Telegram uses a 1000 ms default update interval. Fast
chunks are combined; final output is always flushed. Markdown previews use the
pure StreamRenderer to repair incomplete syntax. Plain text and HTML are kept.

To use edits for a private chat, set `Client.config` to
`[stream_delivery: :edit]`, or pass `options: [stream_delivery: :edit]` on that
call. Supported modes are `:auto` (default), `:draft`, and `:edit`. Explicit draft
mode rejects non-private destinations before it reads the source. The adapter
selects one method before consumption. It does not switch methods after a failed
write or replay the source.

Empty or whitespace streams fail before a provider write. Write failures stop
source consumption and return a typed failure. An unknown outcome can leave a
partial message. The host owns recovery and retries. Resource Enumerables are
closed when a failed write stops consumption. Live subscriptions, durable streams,
and conversation storage belong in Jido Messaging.

The native Action also works in Flow:

```elixir
request = Jido.Chat.Signal.StreamText.new!(%{
  "client_id" => client.id, "request_id" => "stream:1", "room_id" => room_id,
  "format" => "markdown"
})

{:ok, %{signal: completed}} = Jido.Exec.run(Jido.Chat.StreamText,
  %{signal: request}, %{client: client, options: [stream: chunks]}, max_attempts: 1)
```

Use the same Action and context in a Flow step or Router-selected Instruction.

## Provider and test boundaries

```elixir
use Jido.Chat.Adapter
# Required:
channel_type()
capabilities() # %{operation => :native | :unsupported}
invoke(client, request_signal, opts) # canonical result map or error
normalize(client, provider_input, opts) # Delivery or error
# Optional:
default_transport()
operations() # [{provider_request_definition, provider_action}, ...]
event_definitions() # admitted core or provider fact definitions

use Jido.ChatAction,
  name: "provider_operation",
  signal: MyProvider.Signal.Request,
  result_schema: my_result_schema
# Override invoke/3 for provider-specific execution.
```

The shared Action boundary validates requests, client-scoped references, and
results. Requests and results are JSON values. Private options configure transport;
content, formatting, buttons, and routing belong in the request Signal.

```elixir
use Jido.Chat.AdapterTestKit, adapter: MyProvider.Adapter
# In ExUnit tests:
assert_operation_success(result) # accepts Chat and Exec success forms
assert_operation_failure(result) # accepts {:error, %Jido.Chat.Error{signal: failed}}
assert_json_round_trip(signal)
# Provider catalog:
assert_operation_success(result, Jido.Chat.Telegram.catalog())
assert_operation_failure(result, Jido.Chat.Telegram.catalog())
assert_json_round_trip(signal, Jido.Chat.Telegram.catalog())
```

The test kit uses the core catalog by default. Use `Jido.Chat.catalog(client)`
for a configured provider. Result and serialization assertions perform no I/O.
`assert_unsupported_operations(adapter_or_client)` executes every unsupported core
request and requires a typed `unsupported` / `not_attempted` failure. It must not
reach provider I/O. The default test-kit checks include this behavior, capability
declarations, request/event fixtures, and delivery validation. Covenant contracts enforce the core boundary; see [the contract guide](contracts.md).

## Telegram transport boundary

The Telegram adapter implements `channel_type/0`, `capabilities/0`,
`default_transport/0`, `operations/0`, `event_definitions/0`, `invoke/3`, and
`normalize/3` from the core behaviour.
Custom transports implement `Jido.Chat.Telegram.Transport.call/4`:

```elixir
@behaviour Jido.Chat.Telegram.Transport
@impl true
def call(token, method, payload, private_options), do: ...
```

The default implementation is `Jido.Chat.Telegram.Transport.ExGramClient.call/4`.
Its HTTP adapter is `Jido.Chat.Telegram.ExGramAdapter.request/3,4`, implementing
ExGram.Adapter. These are provider wire boundaries. Application operation
contracts should use Actions and Signals. Operations, Normalizer, Membership,
Streaming, and Signal.Schemas contain internal implementation helpers.

## Other public functions


This table lists the remaining documented modules. Action and Signal functions
are listed above. Renderers are pure helpers. Convert their results to the declared
JSON schema before you put them in a Signal. A Card or Modal is a rendering
value, not a portable message payload that every provider can send. The request
schema and declared capabilities determine which operations are available.

| Module | Public functions |
| --- | --- |
| `Jido.Chat` | `actions/0,1`, `add_reaction/4,5`, `capabilities/1`, `catalog/0,1`, `create_thread/3,4`, `delete_message/3,4`, `download_file/2,3`, `edit_message/4,5`, `emoji/1,2`, `event_definitions/0,1`, `execute/2,3`, `fetch_metadata/2,3`, `normalize/2,3`, `operations/0,1`, `remove_reaction/4,5`, `send_message/2,3`, `send_text/3,4`, `start_typing/2,3`, `stream_text/3,4`, `send_file/3,4`, `signal_definitions/0,1` |
| `Jido.Chat.Adapter` | `__using__/1`, `capabilities/1`, `event_definitions/1`, `operations/1`, `render_card/1,2`, `render_markdown/1,2`, `render_modal/1,2`, `render_stream/1`, `validate_capabilities/1` |
| `Jido.Chat.AdapterTestKit` | `__using__/1`, `supported?/2` |
| `Jido.Chat.AdapterTestKit.Assertions` | `assert_capability_coherence/1`, `assert_delivery/2`, `assert_json_round_trip/1,2`, `assert_operation_success/1,2`, `assert_operation_failure/1,2`, `assert_unsupported_operations/1` |
| `Jido.Chat.AdapterTestKit.Factories` | `message_received/1,2`, `operation_request/2,3`, `request/2` |
| `Jido.Chat.Card` | `actions/1,2`, `add/2`, `area_chart/1,2,3`, `bar_chart/1,2,3`, `button/2,3`, `chart/2,3,4`, `divider/0`, `dynamic_select/1,2`, `external_select/1,2`, `fallback_text/1`, `field/2,3`, `fields/1,2`, `from_map/1`, `image/1,2`, `line_chart/1,2,3`, `link/2,3`, `link_button/2,3,4`, `new/1`, `normalize/1`, `pie_chart/1,2`, `radio_select/2,3`, `schema/0`, `section/1`, `select/2,3`, `select_option/2,3`, `select_option_group/2,3`, `table/2,3`, `text/1,2`, `to_adapter_payload/1`, `to_map/1`, `to_markdown/1` |
| `Jido.Chat.Card.ChartData` | `from_map/1`, `new/1`, `schema/0`, `to_map/1` |
| `Jido.Chat.Card.ChartSeries` | `from_map/1`, `new/1`, `schema/0`, `to_map/1` |
| `Jido.Chat.Card.Component` | `from_map/1`, `new/1`, `normalize/1`, `schema/0`, `to_map/1` |
| `Jido.Chat.Client` | `new/2`, `new!/2`, `options/1` |
| `Jido.Chat.Delivery` | `new/3`, `validate/2` |
| `Jido.Chat.Emoji` | `put_custom/3`, `registry/0`, `render/1,2` |
| `Jido.Chat.Error` | `exception/0,1` |
| `Jido.Chat.Errors` | `splode_error?/1,2`, `traverse_errors/2`, `unwrap!/1,2` |
| `Jido.Chat.Errors.Contract` | `exception/0,1` |
| `Jido.Chat.Errors.Validation` | `exception/0,1` |
| `Jido.Chat.Markdown` | `blockquote/1`, `cell/1`, `code/1`, `code_block/1,2,3`, `divider/0`, `emphasis/1`, `from_map/1`, `heading/2`, `link/2,3`, `list/1,2`, `list_item/1`, `new/1`, `paragraph/1`, `parse/1`, `plain_text/1`, `root/1,2`, `row/1`, `schema/0`, `stringify/1`, `strong/1`, `table/1,2`, `table_to_ascii/1`, `text/1`, `to_map/1`, `walk/2` |
| `Jido.Chat.Markdown.Node` | `from_map/1`, `new/1`, `normalize/1`, `schema/0`, `to_map/1` |
| `Jido.Chat.Markdown.StreamRenderer` | `append/2`, `flush/1`, `new/0`, `push/2`, `render/1`, `snapshot/1` |
| `Jido.Chat.MediaType` | `from_filename/1`, `kind/1,2`, `normalize/1`, `resolve/1,2`, `sniff/1` |
| `Jido.Chat.Modal` | `date_input/2,3`, `dynamic_select/2,3`, `external_select/2,3`, `fallback_text/1`, `from_map/1`, `new/1`, `number_input/2,3`, `radio_select/3,4`, `schema/0`, `select/3,4`, `select_option/2,3`, `select_option_group/2,3`, `text_input/2,3`, `to_adapter_payload/1`, `to_map/1` |
| `Jido.Chat.Modal.Element` | `from_map/1`, `new/1`, `normalize/1`, `schema/0`, `to_map/1` |
| `Jido.Chat.Signal.Definition` | `__using__/1` for provider fact definitions |
| `Jido.Chat.Signal.Identity` | `client_source/1`, `conversation_subject/2` |
| `Jido.Chat.StreamChunk` | `fallback_text/1`, `from_map/1`, `markdown_fallback/1`, `new/1`, `normalize/1`, `normalize_many/1`, `schema/0`, `text/1,2`, `to_map/1` |
| `Jido.ChatAction` | `__using__/1` |

## Removed API and host boundary

Removed: `PostMessage`, `PostChannelMessage`, `FetchChannelMessages`, `Stream`,
`OpenThread`, `FetchMedia`, and generic `Signal.OperationCompleted` /
`Signal.OperationFailed`. There are no compatibility aliases.

Use `SendMessage`, `FetchMessages`, pure `StreamRenderer`, `CreateThread`,
`DownloadFile`, and each Action's nested result definitions. `CreateThread` uses
`name`, not `topic_name`. Downloads use `resource_ref`, not `media_ref`.
Trimmed request schemas have new schema versions. Removed fields fail validation.
`Telegram.command_routes/0` is replaced by `operations/0`. Use native
`Jido.Signal.ID` for new Signal IDs. The test kit's old `assert_operation_result/1` is replaced by separate success
and failure assertions with optional catalogs.

Earlier removals include Binding, Resources, RequestStore, Handlers, duplicate
Message/Room/Participant/FileUpload types, raw Adapter helpers, and Telegram
Extensions/FileInfo/options/keyboard structs.

`Jido.Chat.Plugin` adds optional Agent connections. Its public integration calls
are `connections/1` and `ingest/3`; `Jido.Chat.Plugin.Execute` is the terminal
command Action. `Jido.Chat.Sensor` exposes `start_link/1`, `push/2,3`, and
`valid_source?/1`. Providers implement `Jido.Chat.Sensor.Source`: `mode/0`,
`signal_types/0`, and either polling `read/3` or push `start_link/3`. Optional
callbacks are `poll_interval/1` and `key/2`. The DSL selects a provider with
`source Provider.Source, emit: "jido.chat.message.received"`.
See [the complete Agent integration](agent_plugin.md).

Normal SDK startup starts no Chat process or Jido application. AgentServer owns
Plugin and Sensor processes only when the host declares them. Persistent rooms,
identity mapping, history, durable cursors, delivery queues, durable duplicate
records, persistence, and Bus supervision remain host or Messaging work.
Other provider packages need migration to this breaking core version.
