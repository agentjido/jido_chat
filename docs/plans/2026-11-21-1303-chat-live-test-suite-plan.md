---
title: Share live chat adapter tests
type: implementation-plan
date: 2026-11-21
last_reviewed: 2026-11-21
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Share live chat adapter tests

## Goal Capsule

- **Objective.** Provide one opt-in live test suite for Telegram, Discord, Slack, Signal, and X. Use the 38 Telegram cases as the coverage baseline.
- **Means.** Generate ExUnit cases with one test macro. Execute through configured `Jido.Chat.Client` values and the public Chat API. Use provider fixtures for test destinations and provider evidence.
- **Authority.** This request authorizes the plan document. Implementation and live execution require a subsequent request.
- **Stop conditions.** Complete the plan when each Telegram case has a destination and each selected provider can report pass, failure, unsupported behavior, or a setup blocker.
- **Next executor.** A Jido Chat maintainer starts with U1. A test account owner supplies working test resources for live verification.

## Product Contract

### Summary

A maintainer can opt in to one or more providers and run the same Chat behavior checks. Each provider runs the applicable Telegram cases and keeps its unique live checks. A provider with fewer operations gets a smaller suite.

### Problem Frame

Telegram has 21 public API cases and 17 integration cases. The other providers have separate suites, environment gates, and assertions. A shared suite makes equivalent behavior comparable and exposes coverage gaps.

### Actors

- Jido Chat maintainers select the providers and run the suite.
- Test account owners provide credentials, dedicated test targets, and an operator for interactive cases.

### Requirements

- **R1.** Keep live calls opt-in. A default test run must make zero provider calls.
- **R2.** Use one test macro and a shared case catalog. Account for all 38 Telegram cases and the alternate forum case. Preserve the behavior and evidence that each case checks.
- **R3.** Select cases by the adapter's declared operations and the features they need. Report missing credentials, SDKs, or test targets separately from unsupported behavior.
- **R4.** Keep the existing Chat API and optional dependency model. Preserve provider-specific witnesses, extra tests, and stronger assertions.
- **R5.** Use dedicated targets, bounded waits, safe output, and cleanup where the provider allows it. Keep separate opt-ins for manual interaction and X DM writes.

### Key Flows

1. Load the local test credentials and select providers explicitly.
2. ExUnit registers the catalog for each provider. The suite evaluates eligibility and checks setup before any live writes to that provider.
3. A case drives the configured Client. It validates the typed result and, where applicable, checks the actual provider response, saved state, or inbound event.
4. ExUnit reports the outcome for each case. The suite removes resources that it created when cleanup is available.

### Acceptance Examples

- With no provider opt-in, `mix test` and `mix test --include live` make zero provider calls, even with credentials loaded.
- Signal runs send, quote reply, and inline attachment checks. A file round trip reports unsupported because Signal has no core download operation.
- Slack streaming proves one source enumeration and exact final text. Telegram can also prove private previews and edit delivery when its fixture supports them.
- A configured Telegram forum runs the topic routing case. Missing forum configuration is a setup blocker when the routing case is requested. The alternate non-forum rejection case retains its own evidence.
- A selected X credential check that returns 401 fails setup visibly. The read-only selection sends zero DMs.

### Success Criteria

Every baseline case has a traceable disposition. Every eligible case produces a live pass or a named failure or setup blocker. A successful offline suite never counts as live evidence.

### Scope Boundaries

The change covers test code, test config, and provider test instructions in `jido_chat`. Production adapter behavior, authentication changes, and release work are outside scope.

### Key Decisions

Telegram supplies the behavior baseline. The shared suite uses `Jido.Chat` as its public entry point. Native composition, wire checks, and interactive paths retain the entry points required by their contracts.

### Rejected Alternatives

Copying the Telegram modules into each provider would duplicate the contract and tie the new cases to Telegram's wire fields. Each provider supplies evidence for the same behavior through its own fixture.

### Dependencies

Live execution needs the selected provider's existing optional SDKs, credentials, permissions, and dedicated targets. Interactive cases also need a signed-in operator. Polling requires exclusive access to the test bot or account's input stream.

### Outstanding Questions

The prior live run found a refused Signal RPC connection and an X OAuth 401. The test account owner must supply a working Signal endpoint or CLI account and working X OAuth credentials. X write verification also needs an approved DM target. These limits apply to live proof for U5.

### Sources

- [Telegram public API cases](../../test/jido_chat/providers/telegram/public_api_live_test.exs) and [integration cases](../../test/jido_chat/providers/telegram/live_integration_test.exs)
- [Provider setup](../../guides/providers.md), [ExUnit defaults](../../test/test_helper.exs), and [environment template](../../.env.example)

## Planning Contract

### Product Contract Preservation

Product Contract unchanged. This plan derives it from the direct request and adds implementation details.

### Current System

The root test helper excludes `:live`. Telegram has a provider flag and a manual flag. Discord has REST/Gateway and manual UI flags. X has separate authentication and DM flags. Slack relies on ExUnit's live filter and its environment variables. `Jido.Chat.capabilities/1` describes native core operations. `Jido.Chat.operations/1` and event definitions expose provider extensions. These declarations do not establish target permissions, input access, or support for each option of a core operation. [Test helper](../../test/test_helper.exs) · [Chat API](../../lib/jido_chat.ex) · [Adapter contract](../../lib/jido_chat/adapter.ex)

### Target System

Use a single test-only `Jido.Chat.LiveCase` macro under `test/support`. Each provider has one suite entry under `test/live` that passes its adapter and fixtures to the macro. The macro registers ordinary ExUnit tests with `:live`, `:live_provider`, and `:live_case` tags, plus `:live_ui` for interactive cases. Keep selection, assertions, and execution in ordinary functions so the rules can be tested without credentials. Reuse the [AdapterTestKit assertions](../../lib/jido_chat/adapter_test_kit/assertions.ex) for catalog validation and JSON round trips.

Define cases once with a stable ID, required core operations, any extension request or event definitions, feature and target requirements, and a test function. A provider fixture supplies a Client factory, relevant targets and safe inputs, and specific evidence such as saved message state or an observed real response. Shared test functions own the Chat calls and common assertions. A provider supplies a separate test function for unique behavior, such as Telegram draft composition or Discord modal submission. Both enter through the same macro.

### Key Technical Decisions

- **KTD1. Generate tests in test support.** Use ExUnit and the existing Client/Adapter interface. A runtime adapter macro would introduce a production interface for a test requirement. Live suites and fixtures compile in the test environment. Applies to R2 and R4, U1–U6.
- **KTD2. Derive applicability from operations and feature evidence.** Use `Chat.capabilities(client)` for core operations and the configured catalog for extension and event types. Use a small explicit fixture declaration for options and evidence the API does not describe, such as rich HTML, stable edit streams, provider media reuse, or manual callbacks. Require a reason for each feature a provider cannot exercise. Keep fixture expectations independent of the reported capabilities. A missing fixture or witness for a declared applicable case fails coverage. Applies to R2 and R3, U1–U6.
- **KTD3. Use one provider selector and keep existing extra opt-ins.** Propose `JIDO_CHAT_LIVE_PROVIDERS` as an exact comma-separated list, with an empty default and an error for unknown names. Keep `:live` exclusion as a separate guard. Preserve the Telegram and Discord manual flags and the X write flag. During migration, an active shared selector disables all legacy suites. With an empty selector, each legacy suite needs its own explicit provider opt-in. Add a temporary `RUN_LIVE_SLACK_TESTS` gate for the legacy Slack suite and remove the legacy Discord DM recipient fallback. Apply selection before building credentialed Clients, starting Sources, or reading credentials. Applies to R1, R3 and R5, U1 and U6.
- **KTD4. Observe actual effects and bound each run.** For an outbound result, check its catalog, client and request identity, and the provider evidence required by the case. Keep exact byte and event assertions where they exist. Give each run a unique marker, use synchronous suites, and register cleanup as resources are created. Wait for the matching event with a deadline. Keep raw requests, responses, tokens, and private target identifiers out of output. Applies to R2, R4 and R5, U1–U6.

Eligibility has three inputs. The adapter declares the operation, the fixture documents the behavior and supplies suitable evidence, and the run provides the required environment. Evaluate the first two without live calls. Include pure capability and rejection checks in the catalog and execute their reusable assertions with a transport that fails if called.

| Result | Meaning |
| --- | --- |
| Inactive | The provider or the separate manual or write mode was not selected. |
| Unsupported | A required operation or documented feature is absent. Report the requirement. |
| Blocked | An applicable selected case lacks credentials, a dependency, a dedicated target, or a permission. Report the missing prerequisite and return a failing test command for requested coverage. |
| Failed | The case ran and behavior, evidence, timeout, or cleanup failed. |
| Passed | The required assertions passed with the evidence specified by the case. |

Use ExUnit tags for inactive and unsupported cases, where the classification can be made before setup. Use a sanitized preflight assertion for blocked prerequisites. A provider-wide setup failure blocks its live cases. A case-specific setup failure, such as a missing forum target, fails that case before it can write and allows other ready cases to run. If an authorized preflight read receives 401, report the authentication reason and redact the response and credentials. If the provider confirms a known target restriction only on the first attempt, such as Discord refusing delivery to the verified DM recipient, mark delivery blocked and fail the requested delivery check. Keep the lookup result separate. Treat other unexpected provider errors as case failures. An intentionally rejected request can pass only with the expected typed failure and observed provider rejection.

Add a test-only live formatter or equivalent summary that reports each selected provider's case ID, status, and safe reason. Read the tag or preflight result for skipped and blocked cases. ExUnit's default counts alone cannot supply those reasons. Preserve the existing offline formatters.

### Telegram baseline case map

Each row maps a source test to the proof the new suite must preserve. A compound row can generate several capability-specific tests. For example, a lack of `edit_message` must not prevent a `send_message` check. When two rows overlap, share their assertion code and retain both entry points if they prove different contracts. **Common** means a core capability can select the check. **Feature** adds fixture evidence or a mode. **Extension** uses a registered provider operation or fact. **Pure** makes zero provider requests.

| ID | Source case | Eligibility and required evidence |
| --- | --- | --- |
| P01 | [Portable text completion](../../test/jido_chat/providers/telegram/public_api_live_test.exs#L60) | Common. Send text, check provider message, typed completion, client, request, trace, and JSON round trip. |
| P02 | [Rich reply with keyboard](../../test/jido_chat/providers/telegram/public_api_live_test.exs#L82) | Common reply check plus feature checks for rich reply and keyboard. Verify linkage to the prior message and sent content and controls where supported. |
| P03 | [HTML text](../../test/jido_chat/providers/telegram/public_api_live_test.exs#L110) | Feature. Verify HTML delivery through the same facade where supported. |
| P04 | [Lazy source and plain drafts](../../test/jido_chat/providers/telegram/public_api_live_test.exs#L120) | Common stream checked for one enumeration, source closure, execution task termination, and final text. Feature. Verify plain previews and stable draft ID in a suitable private room. |
| P05 | [Markdown preview and final text](../../test/jido_chat/providers/telegram/public_api_live_test.exs#L160) | Feature. Check a stable rich draft ID, safe preview of incomplete Markdown, and exact final content. |
| P06 | [Send-and-edit stream](../../test/jido_chat/providers/telegram/public_api_live_test.exs#L183) | Feature. Verify edit mode keeps one provider message ID. |
| P07 | [Stream coalescing and final flush](../../test/jido_chat/providers/telegram/public_api_live_test.exs#L206) | Feature. Verify Client delivery settings, coalescing, and final flush. |
| P08 | [Inline file and download](../../test/jido_chat/providers/telegram/public_api_live_test.exs#L222) | Common. Check typed upload and scoped reference where provided. Require download capability for the exact-byte round trip. |
| P09 | [Local upload and reference reuse](../../test/jido_chat/providers/telegram/public_api_live_test.exs#L238) | Feature. Test accepted local path sources and reuse of a provider-scoped reference separately. Verify bytes with download support. |
| P10 | [Image delivery and normalized media](../../test/jido_chat/providers/telegram/public_api_live_test.exs#L266) | Feature. Send with `media_kind: :image`, download nonempty bytes from the returned reference where supported, and check caption, dimensions, and the normalized fact's JSON round trip. |
| P11 | [Capability discovery](../../test/jido_chat/providers/telegram/public_api_live_test.exs#L291) | Pure. Check an independent expected matrix and zero calls. |
| P12 | [Edit and clear keyboard](../../test/jido_chat/providers/telegram/public_api_live_test.exs#L315) | Common edit preserves the returned message ID. Feature. Verify control removal. |
| P13 | [Delete and repeat delete](../../test/jido_chat/providers/telegram/public_api_live_test.exs#L344) | Common delete verifies removal by fetch or provider evidence. Feature. Verify the provider's documented repeat-delete outcome. Preserve Telegram rejection. |
| P14 | [Add and remove reactions](../../test/jido_chat/providers/telegram/public_api_live_test.exs#L365) | Common. Check each supported operation against a known sent message and observe its effect. |
| P15 | [Room metadata and trace](../../test/jido_chat/providers/telegram/public_api_live_test.exs#L383) | Common. Compare canonical room data and trace against the actual response. |
| P16 | [Typing acknowledgment](../../test/jido_chat/providers/telegram/public_api_live_test.exs#L411) | Common. Verify one acknowledged notice. Check thread routing where supported. |
| P17 | [Topic creation and routing](../../test/jido_chat/providers/telegram/public_api_live_test.exs#L435) | Common thread creation and send, with a thread-capable target. Check returned ID, parent, and routing. Exercise metadata and typing when applicable. |
| P18 | [Thread rejection](../../test/jido_chat/providers/telegram/public_api_live_test.exs#L477) | Feature. Require a designated negative fixture and an observed provider rejection with a safe typed result. |
| P19 | [Invalid public input](../../test/jido_chat/providers/telegram/public_api_live_test.exs#L492) | Pure. Preserve invalid input and mismatched context checks, zero calls, and zero source reads. |
| P20 | [Real send rejection](../../test/jido_chat/providers/telegram/public_api_live_test.exs#L525) | Feature. Use a designated rejection fixture with no chance of delivery to another user. Check one call, safe failure, request identity, and JSON round trip. |
| P21 | [Pull and normalize updates](../../test/jido_chat/providers/telegram/public_api_live_test.exs#L540) | Extension or live input equivalent. Compare real input facts, identity and ordering, and cursor behavior where applicable. Preserve Telegram's one read without offset and its next offset assertion. |
| A01 | [Native send, edit, and delete](../../test/jido_chat/providers/telegram/live_integration_test.exs#L64) | Common. Exercise the native Action path and typed result for each supported operation. |
| A02 | [Typing, metadata, direct addressing and bot identity](../../test/jido_chat/providers/telegram/live_integration_test.exs#L82) | Common per operation. Keep provider identity lookup as an extension or provider-specific probe. Verify DM lookup separately from delivery. |
| A03 | [Read webhook status](../../test/jido_chat/providers/telegram/live_integration_test.exs#L91) | Extension. Preserve status proof and zero webhook changes. |
| A04 | [Public text and file byte round trip](../../test/jido_chat/providers/telegram/live_integration_test.exs#L98) | Common. Preserve the facade completion checks and exact download bytes. Share setup and assertions with P01 and P08. |
| A05 | [Rich draft stream](../../test/jido_chat/providers/telegram/live_integration_test.exs#L115) | Feature. Verify stable draft ID, exact final rich text, and absence of edit calls in draft mode. |
| A06 | [Explicit send-and-edit stream](../../test/jido_chat/providers/telegram/live_integration_test.exs#L134) | Feature. Verify both writes use the expected content and ID and issue no drafts. Share the P06 scenario where the assertions match. |
| A07 | [Finite render and final send](../../test/jido_chat/providers/telegram/live_integration_test.exs#L154) | Common. Render locally and observe one final send. Require zero drafts when the provider has drafts. |
| A08 | [Explicit drafts in a Flow](../../test/jido_chat/providers/telegram/live_integration_test.exs#L168) | Extension. Preserve two explicit drafts and final send through a native Flow. |
| A09 | [Rich send, reply, edit and finite render](../../test/jido_chat/providers/telegram/live_integration_test.exs#L201) | Feature. Retain the rich format, typed Action results, and reply linkage through these steps. |
| A10 | [Actual reply metadata](../../test/jido_chat/providers/telegram/live_integration_test.exs#L243) | Feature. Verify native reply or quote semantics against the real response. |
| A11 | [Native reaction Actions](../../test/jido_chat/providers/telegram/live_integration_test.exs#L260) | Common. Preserve native Action acknowledgments for each supported operation, alongside P14's facade checks. |
| A12 | [Document metadata and exact JSON bytes](../../test/jido_chat/providers/telegram/live_integration_test.exs#L267) | Common file round trip plus file metadata where registered. Check reference equality, bytes, and decoded JSON. |
| A13 | [Photo, sticker, animation, and video note](../../test/jido_chat/providers/telegram/live_integration_test.exs#L287) | Extension per media type. Verify live normalization, dimensions or duration, provider metadata, and download where supported. |
| A14 | [Native local file source](../../test/jido_chat/providers/telegram/live_integration_test.exs#L328) | Feature. Verify Action accepts a local file and downloading returns its exact bytes. |
| A15 | [Poll through Router and Dispatch](../../test/jido_chat/providers/telegram/live_integration_test.exs#L346) | Extension. Preserve the real provider poll and Router, Exec, Dispatch, and round trip proof. |
| A16 | [Topic route](../../test/jido_chat/providers/telegram/live_integration_test.exs#L373) or [non-forum rejection](../../test/jido_chat/providers/telegram/live_integration_test.exs#L393) | Feature. One existing case slot with two source branches. Preserve both branches, including the actual routed message or the typed failure from the non-forum request. |
| A17 | [Fresh desktop callback and answer](../../test/jido_chat/providers/telegram/live_integration_test.exs#L416) | Feature plus manual opt-in. Match a fresh callback to a unique sent button, answer it, verify the message update, and preserve Dispatch and Bus evidence. |

### System Boundaries and Change Surface

| Surface | Planned change and constraint |
| --- | --- |
| Test registration and preflight | Add the macro, case catalog, and provider suites under test paths. Verify `mix test` ignores them by default. Prove explicit opt-in with a transport sentinel and no provider environment. |
| Fixture and operation boundary | Fixture code may observe or delegate to the real transport. Production API under test performs the behavior. Use case-specific witnesses when a provider returns an acknowledgment or lacks a read API. A witness that only echoes the request cannot prove provider state. |
| Provider targets | Use documented disposable chats, channels, or recipients. No fallback recipient. Negative cases require a provider-specific target that cannot deliver a message. Keep provider-specific ID shapes out of common assertions. |
| Side effects and teardown | Track only IDs generated by the current run. Register cleanup before result assertions when IDs are available. Close Sources, release test processes, and remove temporary files on success or failure. Use one active run per account for polling and interactive cases. Document retained artifacts where cleanup is unavailable, including Signal messages and Telegram topics when using the current cleanup paths. |
| Diagnostics | Show provider, case ID, run marker, status, and safe reason. Mask secrets in assertion messages as well as logs. Bound calls and callback waits. Stop on rate limit or uncertain write outcome without replaying the write. |
| Package and guides | Update the provider testing instructions and `.env.example` with blank or disabled defaults. Use existing dependencies and ExUnit. Keep credentials in the ignored local file. |

### Implementation Units

#### U1 — Opt-in macro and first portable probe

**R1–R5. Dependencies.** None. Add the test-only macro, case registration, provider selection, legacy gates, and live status summary. Port P01 to one Telegram fixture and use a fake transport in offline harness tests. Prove all five outcomes, zero calls for inactive, unsupported, and locally detectable setup blockers, mismatch detection, and secret-safe reporting. Use placeholder credentials and a transport sentinel to prove that broad `--include live` does not activate legacy cases without a provider flag, and that an active shared selector blocks the legacy path. U1 is complete when a provider module can register the same probe with its own fixture and the focused offline checks pass.

#### U2 — Telegram baseline

**R2–R5. Dependencies.** U1. Port the source map to the catalog and the Telegram fixture. Factor duplicate assertions on typed results and transport observation. Keep Telegram's native cases, both A16 branches, P11 and P19, and the separate callback gate. Compare old and new case evidence with a dedicated Telegram bot, including private and forum targets. U2 is complete when all 38 slots and the alternate branch have evidence and tests can run without running both suites in a single invocation.

#### U3 — Discord REST and Gateway

**R2–R5. Dependencies.** U2 case contracts. Apply shared sends, edits, deletions, streams, files, typing, metadata, reactions, threads, and direct lookup where applicable. Keep thread creation from a message through `StartMessageThread`, child thread fetch, edit, history and delete, pagination, archived thread listing, rich embeds, Gateway/Sensor/Agent reply, and the manual button, modal, and slash checks. Verify an explicit DM recipient and report delivery restrictions separately from lookup. U3 is complete when the Discord fixture covers eligible baseline cases and retains the existing Discord-only evidence. [REST suite](../../test/jido_chat/providers/discord/live_api_test.exs) · [Gateway suite](../../test/jido_chat/providers/discord/live_integration_test.exs) · [UI suite](../../test/jido_chat/providers/discord/live_ui_test.exs)

#### U4 — Slack Web API and input

**R2–R5. Dependencies.** U2 case contracts. Port live send, fetch, edit, and delete with the Slack fixture. Add supported checks for stream final content, files, metadata, reactions, and direct lookup. Slack's stream implementation renders before sending. Check that behavior without requiring edit previews. Use the Socket Mode Source for the P21 inbound equivalent when the test app has the event subscriptions, an app token, and a test sender. Evaluate A17 separately using Slack's actual interaction and acknowledgment contract. An interactive Slack equivalent needs its own explicit opt-in and a test operator. U4 is complete when the eligible suite runs against a dedicated Slack channel and the existing fetch proof remains. [Slack suite](../../test/jido_chat/providers/slack/live_integration_test.exs) · [Slack operations](../../lib/jido_chat/providers/slack/operations.ex) · [Slack Source](../../lib/jido_chat/providers/slack/source.ex)

#### U5 — Signal and X direct messaging

**R2–R5. Dependencies.** U2 case contracts. Port Signal text, quote, and inline attachment using its configured CLI or RPC transport. Use its polling Source for a P21 equivalent if a second test account can send a fresh message and the receiver is exclusive to the suite. Port X identity and separately enabled DM delivery. Exercise eligible fetch or delete checks only on approved X DM fixtures with the required access and a safe ownership check. An X inbound equivalent requires an existing authorized Account Activity webhook fixture and separately enabled test input. Record that case's eligibility and setup explicitly. U5 implementation can proceed offline. Its live verification needs a reachable Signal service and working X OAuth credentials and DM recipient. [Signal suite](../../test/jido_chat/providers/signal/live_integration_test.exs) · [Signal Source](../../lib/jido_chat/providers/signal/source.ex) · [X suite](../../test/jido_chat/providers/x/live_integration_test.exs)

#### U6 — Switch the live entry point

**R1–R5. Dependencies.** U2, U3, U4, U5. Adopt the shared path in provider guides and `.env.example`. Remove migrated test bodies only after equivalent case-level proof. Keep any legacy case that still carries evidence until its replacement passes. Verify that one run selects each provider independently, that a multi-provider run isolates outcomes, and that the normal suite sends nothing. U6 is complete when the documentation matches the commands, no baseline or provider-specific test disappeared, and duplicate live suites cannot run by accident.

### Work Graph

U1 supplies the macro and selection contract to U2. U2 supplies the baseline case implementations to U3, U4, and U5. These three units can proceed in parallel. U6 integrates them after parity checks. The first ready unit is U1.

### Verification Contract

Run commands from the package root. The first two are existing commands. The other examples show the proposed runner after implementation. Load only the relevant test settings before a live run.

```sh
mix test
mix test.contracts
JIDO_CHAT_LIVE_PROVIDERS=telegram mix test test/live --include live
JIDO_CHAT_LIVE_PROVIDERS=telegram,discord,slack,signal,x mix test test/live --include live
JIDO_CHAT_LIVE_PROVIDERS=telegram RUN_LIVE_TELEGRAM_UI_TESTS=true \
  mix test test/live --only live_case:A17
```

| Gate | Requirements and units | Evidence and done signal |
| --- | --- | --- |
| Selection and precedence | R1, R3, R5 · U1, U6 | Test disabled, unknown, unsupported, missing setup, expected rejection, and timeout paths with an observer. Only selected eligible cases can attempt live calls. Prove shared and legacy selection are mutually exclusive. Check per-case reasons and confirm that separately disabled human and X writes remain inactive. |
| Catalog traceability | R2–R4 · U2–U6 | Every baseline ID maps to shared checks or retained provider checks. A declared operation that activates a catalog case without an applicable fixture makes the coverage check fail. Independent expected support catches accidental downgrades. |
| Telegram parity | R2, R4, R5 · U2 | Compare typed result, provider-side evidence, and cleanup with the existing suite. Verify the two A16 scenarios in separate runs and perform A17 with a fresh callback. Repeat only selected cases during migration. |
| Other live providers | R2–R5 · U3–U5 | Authorize staging runs per provider and inspect case status. Verify higher-level Discord interaction paths, Slack lifecycle, Signal text and attachment, and X auth and opt-in DM. Record any exact blocked prerequisites as incomplete live evidence. |
| Default and package | R1, R4 · U6 | Run `mix test` and `mix test.contracts`. Repeat the existing core-only consumer check if the test change affects packaging. Confirm the production dependency set and public exports match the baseline. |

### Rollout and Recovery

First add the shared path beside the current provider suites. Compare each replacement with its source cases in separate runs. Switch documentation and remove duplicate bodies after parity. If a test times out after a write, report the run marker and clean up only the resources whose IDs are known. Stop on ambiguous outcomes before another write. Resolve account, recipient, or service problems with the test account owner before another live attempt.

### Risks and Assumptions

- A core operation can support several formats or delivery modes. Test feature eligibility as well as the operation. Use Slack's finite stream and Telegram's draft and edit delivery as separate evidence.
- An empty polling batch proves request and normalization mechanics. It does not prove receipt of a fresh message. Use a matching run marker for callback or fresh inbound proofs. Keep date- or account-dependent interactions opt-in.
- A per-provider live gate depends on current credentials and capabilities. Prior passing Telegram, Discord, and Slack tests establish a useful baseline. They do not prove the proposed harness. Unavailable Signal and X setup is an execution limit.

### Open Planning Decisions

None that block implementation. The account owner supplies the Signal and X test resources before their live acceptance checks. Use provider fixture evidence to select exact targets and mode support during implementation.

### Definition of Done

All six units meet their completion checks. One macro runs the catalog through each provider's configured Client under explicit opt-in. The case map accounts for the 38 baseline slots and the alternate branch, and provider-specific live evidence is retained. Offline and Covenant gates pass. Live acceptance requires passing evidence for each provider's eligible cases and requested manual modes. A blocked live check keeps that provider's live acceptance open. The guides describe setup, selection, reporting, and retained fixtures.

### Planning Sources

- [AdapterTestKit](../../lib/jido_chat/adapter_test_kit.ex) and [Mix test paths and dependencies](../../mix.exs)
- [Telegram](../../lib/jido_chat/providers/telegram/adapter.ex), [Discord](../../lib/jido_chat/providers/discord/adapter.ex), [Slack](../../lib/jido_chat/providers/slack/adapter.ex), [Signal](../../lib/jido_chat/providers/signal/adapter.ex), and [X](../../lib/jido_chat/providers/x/adapter.ex) capability declarations
- [Telegram live instructions](../../guides/providers/telegram.md), [Discord](../../guides/providers/discord.md), [Slack](../../guides/providers/slack.md), [Signal](../../guides/providers/signal.md), and [X](../../guides/providers/x.md)

## Adapter Results

- Markdown is the canonical plan in this file.
- HTML and Beadwork are outside the requested output.
