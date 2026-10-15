# Chat and Messaging checkpoint: B0–B2

B0, B1, and B2 are complete. G0–G3 have passed. G4–G9 remain pending.
Execution stopped at B2, as the user requested. Adapter work did not start.

| Check | Result |
| --- | --- |
| Chat package tests | 257 passed |
| Messaging inclusive tests | 2,006 passed |
| Core runtime profile | 2,006 passed |
| Optional AI runtime profile | 2,006 passed |
| Runtime harness, each profile | 241 passed |
| Optional AI fixtures | 4 passed; no model call |
| Chat and Messaging quality | Passed |
| Native catalog | 110 definitions passed |
| Compiled API audit | 4,071 exports; zero failures |
| Public boundary scan | 369 library files; zero findings |
| Messaging coverage | 11,214 / 12,453 relevant lines: 90.05059% |

The tracker now has clear gate dependencies. G3 has seven finite acceptance
rows. Coverage remains a required G7 check and passes at this candidate.
Future source changes require a refresh of affected evidence.

The unfinished route result tests are saved. The new tests cover facade defaults,
scoped storage, migration rollback, configuration input, route fallback, media
failure/retry, bounded reconnects, credential revocation, and native event data.
There are 49 new tests and four saved unfinished tests. No coverage threshold,
exclusion, or live/skip tag was changed.

Two faults were corrected. A nil value is removed from adapter content
capabilities. Malformed nested bridge configuration now fails before a room is
created. The Chat library source is unchanged.

## Saved work

| Repository | Commit | Change |
| --- | --- | --- |
| Messaging | `35ed1e6` | Save route result and resource ownership tests |
| Chat | `c7eb9f7` | Save B0 evidence and correct tracker dependencies |
| Messaging | `416ae44` | Filter nil capabilities and verify bridge contract |
| Messaging | `583e00e` | Reject malformed nested topology configuration |
| Messaging | `08b87e1` | Verify facade defaults, storage, and route fallback |
| Messaging | `17db6f1` | Verify media, reconnect, identity, and event contracts |

Commit `416ae44` says 53 focused tests. The actual combined focused log records
51 tests. Commit `17db6f1` records the correction. Git history was kept.

The [machine-readable report](checkpoint-b0-b2.json) lists all seven G3
acceptance rows and exact checks. The
[evidence folder](evidence/checkpoint-b0-b2/) contains command results, source
hashes, graphs, and logs. Passing checks used unchanged source during each run.

Membership/adapter completion, whole-group C01–C14 conformance, package release
readiness, PR review, and current-head CI remain in G4–G9. No PR, merge, release,
live provider operation, or GitHub issue progress update was performed here.
