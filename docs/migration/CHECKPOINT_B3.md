# Membership and Telegram/Slack checkpoint: B3

B3 is complete. G4 and G5 pass their own acceptance reports. G0–G5 now pass.
Execution stopped at B3. B4–B6 did not start. G6–G9 remain pending.

| Check | Result |
| --- | --- |
| Telegram non-live tests | 243 passed; 16 existing live exclusions |
| Slack non-live tests | 142 passed; 8 existing live exclusions |
| B3 cross-package tests | 129 passed |
| Shared runtime harness | 241 passed |
| Pinned Telegram/Slack graph | 44 dependencies; passed |
| Telegram and Slack quality | Passed; zero Dialyzer errors or skips |
| Frozen event rows | 34 passed across all declared forms |
| Frozen operation rows | 52 passed; exact calls, cache, JSON and trace checked |
| Telegram coverage | 1,056 / 1,323 lines: 79.81859% |
| Slack coverage | 1,053 / 1,421 lines: 74.10274% |

Membership tests cover join, leave, removal, role and restriction changes,
restricted `is_member`, bot-self, absent actor and absent prior state. Native
facts pass JSON round trips. Repeated items cause one semantic observation under
the declared memory rule. Membership causes zero message-handler, mention-handler,
agent, provider, grant, canonical membership, canonical persistence or presence effects.
Telegram rejects a failed batch without advancing its checkpoint. Participant
queries remain separate; Slack observed participant sets retain `complete: false`.

Three Slack faults were fixed. Sink exceptions no longer stop the Socket worker.
Private controls now use the room from container or view data. Deliveries that
contain only normalization failures release their controls. Ordinary envelopes
retain ack-before-sink order. Response-bearing envelopes retain sink-before-ack
order. All delivery limits cause zero sink and ack calls. An acknowledgement does
not provide a new durable acceptance guarantee.

Modal tests check two bindings with the same provider view ID, separate room
subjects, cancelled and expired resources, owner exit and binding closure.
Global shortcuts and unknown views have no known room under the frozen schema.
They produce typed normalization failures and release controls. No room is invented.
Interaction tokens and private media stay outside public Signal data. Resources
remain call-local; restart-safe replay is not claimed.

Real adapter calls pass through Messaging: Telegram send and typed unsupported
history, Slack send, a complete cursor-bearing history page and a private modal
response. Both providers pass membership and media ingress. Source or subject
mismatch selects zero events. Payload policy stays in the application.

No live provider traffic was used. No exclusion, skip tag, coverage threshold,
upstream pin or release scope changed. Telegram and Slack coverage has no new
minimum. Messaging retains its required 90 percent minimum and its B0–B2 proof
of 90.05059 percent on unchanged source. Chat, Messaging and Signal provider
library/package test hashes match that proof. Their full suites were not rerun.

## Saved work

| Repository | Commit | Change |
| --- | --- | --- |
| Slack | `f124463` | Contain sink faults; check all Socket delivery limits |
| Slack | `78df382` | Retain private room scope; release rejected controls |
| Telegram | `8688a30` | Check every polling limit and retry checkpoint |
| Chat | `ce4fc3a` | Complete the frozen pair matrix and real runtime tests |

## Acceptance evidence

[G4 membership acceptance](evidence/checkpoint-b3/g4-acceptance.json) maps nine
conditions to named assertions. [G5 adapter acceptance](evidence/checkpoint-b3/g5-acceptance.json)
maps eight conditions. The [checkpoint record](evidence/checkpoint-b3/checkpoint-report.json)
contains final commands, results and source hashes. [Source verification](evidence/checkpoint-b3/source-verification.json)
confirms all final checks match the saved source. Expected failing regression
logs and two corrected fixture errors remain in the evidence folder.

Technical acceptance for membership issue #57 is complete. The issue remains open;
closure requires its agreed acceptance scope. No GitHub issue was changed.

The next batch is B4: the remaining seven adapters, G6. Full-group conformance,
coverage refresh, documentation/version checks, review, PRs and current-head CI
remain required in G7–G9. No B3 acceptance defect remains open.
