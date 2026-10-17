# B4 result: complete

G6 passed. All nine adapter rows are implemented and locally verified. The seven
remaining adapters meet the six acceptance rows in the closeout plan. Execution
stopped after B4, as requested. B5 and B6 did not start. G7–G9 remain pending.

| Adapter | Passed tests | Existing exclusions | Quality | Coverage | Source commit |
| --- | ---: | ---: | --- | --- | --- |
| Telegram | 243 | 16 | pass | 79.8% | 8688a30 |
| Slack | 142 | 8 | pass | 74.1% | 78df382 |
| Discord | 108 | 9 | pass | 80.5% | b45c22d |
| GitHub | 71 | 1 | pass | Not measured | 104e7a9 |
| Signal | 80 | 1 | pass | Not measured | 10db758 |
| Mattermost | 153 | 4 | pass | 91.5% | 13b43f5 |
| Teams | 87 | 2 | pass | 75.5% | 0522afe |
| WhatsApp | 98 | 13 | pass | 80.8% | 0b6c32d |
| X | 62 | 2 | pass | Not measured | 5242a25 |

Mattermost meets its 90 percent floor. WhatsApp meets its 80 percent floor.
Other shown coverage values are measurements; no new floor was introduced.
Telegram and Slack retain B3 quality/coverage proof. Their current suites and
129 shared runtime fixtures passed after the core schema changes.

The combined G6 fixtures passed 382 tests. Chat passed 260 tests and its quality
gate. All 110 catalog definitions passed. The complete graph has 11 local packages,
72 dependencies and the frozen upstream refs. The source scan checked 471 library
files across all 11 packages and found no prohibited paths.

All 297 original literal case names remain. Tests now check typed facts and private
provider values where the old DTO path was removed. Existing live/integration
exclusions remain. No exclusion was added. These checks used local fixtures.

The adapters retain complete input units, ordered facts, exact callback counts,
cached results, typed failures and private resource controls. Teams retains all
members/reactions. X retains every DM. WhatsApp sends one complete upsert to the
sink. Mattermost and Signal normalize before acceptance. GitHub retains lifecycle
distinctions. Discord does not infer room membership from guild role changes.

Two core schema corrections add no fields. MessageUpdated text remains required
and permits null; the user approved this change. ReactionRemoved reaction remains
required and permits null when an Amarula clear gives no previous emoji. A recorded
B4 defect explains that correction. Added/removed reaction commands are unchanged.
Discord, GitHub and X now map the authenticated raw body. Discord HTTP ingress
requires a captured public key.

Code and evidence are saved in local progress commits. No live provider traffic,
CHANGELOG edit, push, PR, merge or publication occurred. Earlier failed commands
and saved recovery patches remain as historical evidence. Push ingress has no new
durable checkpoint or replay guarantee.

The next work is B5: the G7 C01–C14 report and complete candidate verification.
Package readiness and PR delivery follow in B6. The overall goal is incomplete.

See [the machine-readable report](evidence/checkpoint-b4/checkpoint-report.json),
[the adapter matrix](adapter-matrix.json), and
[the original case translation record](evidence/checkpoint-b4/original-test-case-translation.json).
