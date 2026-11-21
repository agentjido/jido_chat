# Discord operation and evidence matrix

This audit covers all 23 current `Jido.Chat` operations. Native means implemented
by this adapter. Unsupported means the adapter rejects the operation before I/O;
it does not always mean that Discord has no related API. No unsupported row is
counted as a successful live feature test.

`test/jido_chat/providers/discord/live_api_test.exs` is the repeatable provider suite.
`test/contracts/providers/discord/adapter_contract_test.exs` checks all 23
capability states, fixed wire cases, client isolation, and unsupported requests.
`test/contracts/providers/discord/actions_contract_test.exs` checks all eleven
convenience helpers, streams, files, Flow, and native execution.
`test/contracts/providers/discord/signals_contract_test.exs` checks all nine native
identities and three independent request schemas. They also check constructor
privacy, context, options, and encoded size. Fixtures are checked in and are not
rewritten by tests.

| Operation | Capability | Public facade | Local evidence | Live evidence / limit |
| --- | --- | --- | --- | --- |
| send_message | native | send_text, send_message | adapter/Action contracts; operations tests | text, reply, exact message ID |
| stream_text | native | stream_text | adapter/Action contracts; operations tests | finite stream, one final message |
| send_file | native | send_file | adapter/Action contracts; operations tests | exact uploaded/downloaded bytes |
| edit_message | native | edit_message | adapter/Action contracts; operations tests | fetch proves changed text |
| delete_message | native | delete_message | adapter/Action contracts; operations tests | fetch proves deletion |
| start_typing | native | start_typing | adapter/Action contracts; operations tests | Discord 204 acknowledgement |
| fetch_metadata | native | fetch_metadata | adapter/Action contracts; operations tests | exact channel ID, name, kind |
| fetch_thread | native | execute | adapter/Action contracts; operations tests | exact created thread and parent |
| fetch_message | native | execute | adapter/Action contracts; operations tests | exact ID, text, reply identity |
| download_file | native | download_file | adapter/Action contracts; operations tests | fresh CDN URL and exact bytes |
| open_dm | native | execute | adapter/Action contracts; operations tests | exact room and verified recipient; extra DM delivery blocked |
| create_thread | native | create_thread | adapter/Action contracts; operations tests | created thread and parent |
| add_reaction | native | add_reaction | adapter/Action contracts; operations tests | read provider reaction state |
| remove_reaction | native | remove_reaction | adapter/Action contracts; operations tests | read provider reaction state |
| fetch_messages | native | execute | adapter/Action contracts; operations tests | forward/backward cursor pages |
| list_threads | native | execute | adapter/Action contracts; operations tests | public archived threads and timestamp cursor |
| get_user | unsupported | execute | adapter.I2: rejected, zero calls | adapter has no user query implementation |
| fetch_subject | unsupported | execute | adapter.I2: rejected, zero calls | adapter has no subject projection |
| get_thread_participants | unsupported | execute | adapter.I2: rejected, zero calls | adapter has no participant pagination implementation |
| mark_as_read | unsupported | execute | adapter.I2: rejected, zero calls | bot API has no user read-state operation |
| post_ephemeral | unsupported | execute | adapter.I2: rejected, zero calls | core request has no interaction ID; use native interaction Action |
| open_modal | unsupported | execute | adapter.I2: rejected, zero calls | core request has no interaction ID; use native interaction Action |
| load_options | unsupported | execute | adapter.I2: rejected, zero calls | Discord autocomplete is an interaction response, not a provider query |

## Extensions and incoming input

| Boundary | Local proof | Live/UI proof |
| --- | --- | --- |
| SendRichMessage | exact embeds, components, routing, JSON schemas | passed: stored embeds/components and real UI buttons |
| StartMessageThread | exact message-thread path and parent | provider thread on a known message |
| RespondInteraction | private controls; response enum 4,5,6,7,9; missing/foreign/expired context | passed: fresh button callback, modal open/submit, slash reply |
| normalize | fixed message, edit, delete, reaction, thread, slash, button, modal fixtures | passed: Gateway messages and real button/modal/slash input |
| Webhook.verify | Ed25519 signed fixed body; changed/missing headers rejected | pure host helper, no live HTTP server required |
| Source | heartbeat, ACK, resume, intents, session reset, stale frames, rejection, shutdown | Gateway -> shared Sensor -> V3 Agent -> Chat reply |

The Source uses one shard. Admission is not durable storage. New workers have no
saved session. Interaction tokens stay private and need a host-owned path; no
handle or credential is placed in public Signals.

## Shared contract limits

Core edit/delete/reaction/single-message query schemas have no `thread_id`.
Direct Client calls use the thread channel as `room_id`. An Agent connection
limited to the parent room cannot use that method without changing its allowed
rooms. Tests must not bypass that allowlist.

The optional Source `:interaction_sink` is an explicit host MFA. It runs before
normalization and Sensor admission. It receives private client, bot, room, and
interaction identity, a token, and the local receipt time. Sink failure stops the
worker before admission. Bare token options are not supported because Core can log execution options on
failure. The private struct has redacted Inspect output, and a controlled provider
rejection checks the Core error log for token disclosure. The Action checks those
identities and rejects controls
at or beyond three seconds. There is no implicit token store or shared SDK API.
The normal Agent Plugin does not supply per-interaction private execution options.

The live host example in `test/support/providers/discord/live_interaction_host.ex` owns a bounded
store, atomic removal, expiry, and process cleanup. It connects a public Agent
Action to Chat execution with private controls. The host must also handle replay,
failed admission, room checks, and shutdown. Source admission is not a promise of
a reply. A rejected event can follow an accepted event; a restarted Source/Sensor
has no saved session or deduplication history.

Worker status and OTP error-report tests cover raw frames, debug logs, process
dictionaries, and safe failure categories. The Gateway worker and its Mint
connection process set the Erlang sensitive flag.

## Results

Standalone Discord adapter validation on 2026-10-18, before consolidation:

| Gate | Result |
| --- | --- |
| Format and warnings-as-errors compile | passed |
| Full package quality gate | passed; Dialyzer 0 errors and 0 skipped warnings; Doctor 0 failed modules |
| Default local tests | 61 passed; 12 live tests excluded |
| Production coverage | 96.7%; minimum remains 90%; only test files are excluded |
| Covenant runtime | 21 tests passed; 20/20 active obligations, 100% |
| Covenant static | 20/20 active obligations, 100% |
| Live API and message Source/Agent proof | 11 tests passed |
| Fresh live UI proof | 1 test passed; four actual interactions |
| Extra direct-message delivery | blocked by Discord `forbidden`; OpenDm passed |

The capability matrix has 16 native core operations, seven unsupported core
operations, and three native extension Actions.

Live UI evidence from 2026-10-18, `agentjido-test / bridge`:

| Input | Interaction ID | Response time | Provider/UI result |
| --- | --- | --- | --- |
| Button callback | 1561468161843527751 | 268 ms | type 7; stored message text and visible update matched |
| Open modal | 1561468183947247727 | 201 ms | type 9; actual form opened |
| Submit modal | 1561468197318819941 | 223 ms | type 4; exact `answer=jido-ui-proof`, visible reply |
| Slash command | 1561468254021746748 | 258 ms | type 4; exact temporary command, visible reply |

Temporary UI message `1561468129987535012` and command `/jido-proof-5442` were
removed by test cleanup. The host store was empty. The message Source proof
also checked that Agent shutdown closes the Gateway socket. Its final exact
message/reply pair was `1561467600154792047` → `1561467600855240771`.
Thread cleanup also removes Discord's generated type-18 notices. The remaining
older test threads were emptied of their known bot test replies, then removed.
Normal starter messages and user messages were preserved. Both runs' ephemeral UI replies were checked in the app and then dismissed.

The signed-in Discord user was verified in the app as `mikehostetler`. The known
bridge message `spike three 1792351437517295` had that same username and author ID
`281856954903691264`. OpenDm returned room `1561465237650022400`; provider data
confirmed that recipient. Discord rejected the extra send to this room with
`forbidden`. This is a provider restriction, not a successful DM delivery claim.
The remaining live operations use the authorized bridge channel.

The API tests assert exact created message/thread IDs, reply identity, parent
routing, message state after edits/deletes, forward/backward history cursors,
archive timestamp cursors, reaction state, and uploaded/downloaded binary bytes.
Every typed request checks request ID, operation, causation, trace context,
client source, and catalog validation. Existing messages are not deleted.
