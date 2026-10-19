# Static SDK design

The current API is defined in [the full public API reference](public_api.md).
It includes all 23 core Actions, 86 core Signal definitions, 14 Telegram Actions,
files, keyboards, Flow, Router, provider callbacks, and migration notes.

Clients are immutable values. Requests, events, and results are native Jido
Signals. Operations are native Jido Actions. Every Action defines its own
Completed and Failed Signals. The same Action works through Exec, Flow, and a
Router-selected Instruction.

A call has explicit inputs and no retained SDK state. Invalid requests and
unsupported operations fail before provider I/O. A provider failure preserves a
safe outcome: not_attempted, rejected, or unknown. A request ID is correlation;
it does not make a provider write idempotent. The host controls retry policy.

Use `send_text`, `stream_text`, `send_file`, `edit_message`, `delete_message`,
`download_file`, `add_reaction`, `remove_reaction`, `fetch_metadata`, `start_typing`,
and `create_thread` for common calls. They build
Signals and run the existing native Actions. `capabilities(client)` reads the
adapter's declared support without I/O. StreamText passes its lazy source in private
context. The adapter selects incremental delivery. Jido.Exec owns its temporary
execution tasks. Jido Chat owns no worker or stored stream state.
Use one SendMessage path for rooms and channels. Render finite chunks with the
pure StreamRenderer before sending. CreateThread creates by name; existing
threads are addressed with SendMessage.thread_id. DownloadFile consumes a
resource_ref. Telegram GetFile returns metadata through the same file resolver.
`start_typing` sends one notice, with an optional thread ID. The host owns any
timer that repeats it. `fetch_metadata` reads room data once without a cache.

Construction and discovery start no process. The host owns listeners, polling,
offsets, background scheduling, queues, storage, duplicate checks, Signal publication,
and Bus supervision. Those services belong in Jido Messaging or the hosted app.

`execute(client, request, options: private_options, timeout: 30_000)` selects core
or configured provider Actions. Main helpers use the same options. Deadlines do
not imply cancellation at the provider or make a write safe to retry. Agent Action
schemas expose the full Signal envelope and typed request data. Serialized Action
input is decoded before execution.

Use `actions(client)`, `operations(client)`, `signal_definitions(client)`, and
`catalog(client)` for configured discovery. `event_definitions(client)` declares
which incoming facts normalization can return. Providers can add fact definitions
through `Jido.Chat.Signal.Definition`. Facts stay native Signals.

Telegram `FetchUpdates` reads one update batch and uses the same normalizer as
webhooks. Forum service updates become ThreadStarted or ThreadChanged facts.
The host decides when to store and pass the next offset. Pulling new updates does
not add history storage or a polling service to the SDK.

Covenant contracts enforce the public API, Actions, Signals, adapters, and application metadata. See [the contract guide](contracts.md).
