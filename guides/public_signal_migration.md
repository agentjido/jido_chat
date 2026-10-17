# Public Signal migration guide

This release changes the public communication API. The intended release is Chat
2.0, Messaging 2.0 and the adapter versions in version-matrix.json. The current
scope has eight adapters. Mattermost is excluded by user instruction.

## Consumer changes

| Previous use | New use |
| --- | --- |
| Event envelopes and public provider DTOs | Shared Jido.Chat.Signal facts in a complete Jido.Chat.Delivery |
| Provider callbacks from application code | Jido.Chat.bind/2 and typed commands or queries through Jido.Chat.execute/2 |
| Runtime ingress wrappers | Instance.accept_delivery/1 with the unchanged normalized parent facts |
| Event-type and payload routing | Native Bus selection by type, exact source and exact subject |
| Agent dispatch from provider membership changes | MembershipObserved facts; runtime grants, membership and presence require explicit actions |
| Projection into a local signal catalog | Jido.Signal.Catalog with Chat and Messaging definition lists |
| Inline file or stream ownership | Private resources scoped to the configured binding, actor and owner |

Pure message, room, participant, card and Markdown value builders remain where
listed in api-map.json. Removed wrappers are listed in core-retired-modules.json.
The mapping files describe each retained or removed public API.

## Typed operation example

Bind the provider once with its private settings. Keep those settings outside
signal data. Construct a shared SendMessage with request_id, room_id and text.
Call Jido.Chat.execute(binding, request). The result is an OperationCompleted or
OperationFailed signal. Repeating an admitted request uses its recorded result.

The complete runnable example uses a local Signal transport and checks one
callback, direct cause, trace and native JSON round-trip:

Check out Chat, Messaging and all eight adapters as sibling directories. Use
each PR's source commit from the final delivery index. The integration project
fetches the upstream Git commits from version-matrix.json. The saved absolute
paths identify the original test machine; local resolution uses sibling paths.

    cd jido_chat/integration
    MIX_ENV=test JIDO_INTEGRATION_PROFILE=all JIDO_INTEGRATION_AI=0 mix deps.get
    MIX_ENV=test JIDO_INTEGRATION_PROFILE=all JIDO_INTEGRATION_AI=0 mix run examples/native_contract.exs

No provider credentials or live traffic are required by this example.

## Delivery and runtime ownership

Normalize one complete provider input unit. Pass the delivery to the captured
Messaging sink. Keep input order and stable item identities. Inspect item failures
instead of dropping malformed items silently. A repeated accepted item does not
write another record or publish another observation.

Messaging preserves accepted parent IDs and payloads. Runtime child signals use
the parent as their direct cause and retain its trace. Provider membership facts
do not become messages, invoke message handlers, trigger agents or create grants.

Queries use typed items and opaque cursors. Streams remain lazy. Resource expiry,
cancellation, owner mismatch and provider failures produce defined typed results.
The adapter matrix lists native, fallback and unsupported behavior for every
operation. Unsupported behavior is a checked contract result.

## Limits and startup

A signal is limited to 262,144 encoded bytes. A delivery is limited to 1,048,576
encoded bytes, 100 signals and 20 item failures. Configure a protocol-1 adapter
before starting listeners. Invalid protocol or configuration must fail at startup.

Core owns the shared signal definitions. Messaging owns runtime records, grants,
routing and retries. A provider adapter owns verification, private transport and
mapping. The Signal provider owns the Jido.Chat.Signal parent module.

## Package and publication decisions

The version matrix records intended release versions and immutable upstream refs.
Dev/test source pins and explicit local paths support integration before those
versions are published. Production metadata requires the intended Hex releases.
A successful local package build does not prove those releases are available.

Messaging proposes Jido AI 3.0 for production. The published Jido AI 2.3 and
2.4 packages require Jido 2.x and cannot meet this migration's Jido 3.x contract.
Development and test use the exact compatible Jido AI source commit in the
version matrix. Publication must wait for a compatible Jido AI 3.0 release.
Chat 2.0 and the new consumer package versions must also be published in order.
The published Signal, Jido, Action and Zoi libraries differ from the tested Git
commits. The published Signal beta lacks the Catalog and router DSL used here.
Publication must use compatible upstream releases with the required APIs and
fixes. See release-readiness.json and published-source-comparison.json in the
current evidence folder.

Publish compatible upstream dependencies first, then Chat, then Messaging and
provider adapters. This task prepares reviewable PRs; publication and merges
require separate instructions. Keep every rollback pin in version-matrix.json.
Consumers must move to the new contract as one compatible dependency set.

CVE-2026-43966 for Cowlib 2.21.0 and Gun 2.7.0 is accepted by the user. The report
retains the failed raw audit and the exact exception. Other findings are not
accepted. See audit-exceptions.json.
