# B4 status: decisions required

B4 is incomplete. G6 remains pending. No provider has a G6 signoff yet.
G0–G5 remain passed. B5 and B6 did not start.

Discord source and channel test migration is in progress. The scoped checks pass
41 of 42 tests. The remaining failure is a valid partial update with no text.
The frozen shared MessageUpdated schema requires a string, so it cannot retain
that fact. A proposed correction allows string or null without adding a field.
The schema and matching catalog are unchanged.

Automatic approval review rejected a scripted replacement of the Discord Gateway
test file. It called the replacement broad and unreviewed. The original file is
unchanged. The proposed conversion retains all ten original test names and checks
native deliveries. Approval was requested in the current chat.

| Check | Result |
| --- | --- |
| Discord scoped cases | 41 passed; 1 shared schema failure |
| Signal existing package tests | 54 passed; 1 existing live exclusion |
| Signal package quality | Passed |
| Discord, GitHub, Mattermost dependencies | Prepared |
| Final seven-provider matrix and G6 | Pending |

Signal's existing checks are preparation evidence. They do not complete its final
G6 event/resource/transport signoff. GitHub, Mattermost, Teams, WhatsApp and X still
need their native mapper and original test conversions. Discord still needs its
Gateway tests, complete operation/event matrix, and full package checks.

[The pending record](evidence/checkpoint-b4/pending-report.json) lists all source
states and decisions. [Saved work](evidence/checkpoint-b4/saved-work/) contains a
compressed Git patch for each provider, plus the two proposals. The original case inventory has
297 named source cases; generated operation cases add their own runtime counts.
No source work was committed because implementation and checks are unfinished.
No live traffic or new exclusions were used. No CHANGELOG was changed.

The next action is to resolve the two decisions, then finish B4. Stop after G6.
