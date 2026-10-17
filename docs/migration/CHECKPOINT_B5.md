# B5 result: checks finished; G7 failed

Execution stopped after B5. C01–C13 pass. C14 fails because the Mattermost
package build fails. All required checks have results. B5 does not meet its
completion rule. G0–G6 remain passed. G8 and G9 remain pending. B6 did not start.

| Check | Behavior | Result |
| --- | --- | --- |
| C01 | Native constructors and lossless JSON | pass |
| C02 | Rejected unsafe values and overrides | pass |
| C03 | Complete deliveries, order and limits | pass |
| C04 | Duplicate units and exact counts | pass |
| C05 | Authorization and zero-call failures | pass |
| C06 | All 26 operations for nine adapters | pass |
| C07 | Queries, streams and private resources | pass |
| C08 | Parent identity, child cause and trace | pass |
| C09 | Membership isolation | pass |
| C10 | Type/source/subject selection | pass |
| C11 | Handlers, broadcast, retry and checkpoints | pass |
| C12 | All adapter support claims and source/API checks | pass |
| C13 | Both complete runtime profiles | pass |
| C14 | Package file lists, metadata, example and local index | fail |

Both full nine-adapter profiles pass 260 Chat tests, 2,006 Messaging tests,
244 harness tests and 521 adapter fixtures. The optional AI check passes four
tests. The report checks 110 native definitions, 234 operation rows and 153 event
rows. The API check covers 4,818 compiled exports. The source scan checks 471
library files across all 11 packages and finds no prohibited paths.

| Package | Passed tests | Existing exclusions | mix quality | Audit | Package build |
| --- | ---: | ---: | --- | --- | --- |
| jido_chat | 260 | 0 | pass | pass | pass |
| jido_messaging | 2006 | 0 | pass | pass | pass |
| jido_chat_telegram | 243 | 16 | pass | pass | pass |
| jido_chat_slack | 142 | 8 | pass | pass | pass |
| jido_chat_discord | 108 | 9 | pass | fail | pass |
| jido_chat_github | 71 | 1 | pass | pass | pass |
| jido_chat_signal | 80 | 1 | pass | pass | pass |
| jido_chat_mattermost | 153 | 4 | pass | pass | fail |
| jido_chat_teams | 87 | 2 | pass | pass | pass |
| jido_chat_whatsapp | 98 | 13 | pass | pass | pass |
| jido_chat_x | 62 | 2 | pass | pass | pass |

| Coverage | Measured | Required | Result |
| --- | ---: | ---: | --- |
| Messaging | 90.05059% | 90% | pass |
| Mattermost | 91.56415% | 90% | pass |
| WhatsApp | 80.83333% | 80% | pass |

The exact covered and relevant line counts are in the machine report. No
coverage floor was lowered. No exclusion was added. Existing provider test names
are retained; the B4 translation record remains valid because those files did
not change.

The complete graph and the Discord audit fail on Cowlib 2.21.0 and Gun 2.7.0
with CVE-2026-43966. The Discord source has existing ignore flags. The G7 audit
uses a temporary copy with those flags cleared. No audit exception was accepted.
See the [full audit log](evidence/checkpoint-b5/g7-all-audit.log) and the
[Discord audit log](evidence/checkpoint-b5/g7-jido_chat_discord-audit.log).

Mattermost has no license metadata. The user specified no license. Its Fresh
dependency uses Git, which Hex excludes from packages. The required build fails
for both reasons. No license was added or inferred. See the
[build log](evidence/checkpoint-b5/g7-jido_chat_mattermost-package-build.log).

Ten package archives pass file-list, source-byte and production constraint
checks. These are local builds. Release versions, dependency availability and
publication readiness remain in B6.

The local candidate index passes for all 11 packages. It includes branches,
source hashes, rollback pins and check links. The user selected local index
verification for C14; PR delivery remains in B6. PR URLs are null and CI is not
started. The native example passes with one provider callback. These results
do not remove the Mattermost package failure from C14.

The report hash check had inconsistent file ordering. It now uses the same
path-component order as the command recorder. Runtime proof is reused only when
the exact old report-control tree can be reconstructed from the saved source.
All other files must match. Both current harness suites and compile checks
passed after the correction. Historical source snapshots were not rewritten.

Tested source changes and this report are saved in local progress commits.
The index records source commits. The final evidence commit changes documentation
only. Its SHA is in Git history; the checked source hashes remain valid.
No live provider traffic, CHANGELOG edit, push, PR, merge or publication occurred.
The goal remains incomplete. G7 must pass before B6 can start.

See the [machine report](evidence/checkpoint-b5/checkpoint-report.json),
[conformance report](evidence/checkpoint-b5/conformance-report.json),
[local candidate index](evidence/checkpoint-b5/candidate-index.json), and
[package index](evidence/checkpoint-b5/package-index.json).
