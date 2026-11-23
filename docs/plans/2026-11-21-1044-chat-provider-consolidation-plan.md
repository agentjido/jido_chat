---
title: Consolidate five adapters in Jido Chat V3
type: implementation-plan
date: 2026-11-21
last_reviewed: 2026-11-21
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Consolidate five adapters in Jido Chat V3

## Goal Capsule

- **Objective** — Ship Discord, Telegram, Slack, Signal Messenger, and X in the `:jido_chat` Mix package. Make the standalone packages eligible for deprecation.
- **Means** — Move each V3 adapter and its evidence into the core repository. Preserve its public modules. Make each provider transport dependency optional for host apps.
- **Authority** — This request authorizes the plan document. Code changes, publication, retirement, and repository archival require separate authorization.
- **Stop conditions** — Stop a provider move if its V3 public contract or supported behavior cannot be preserved. Hold publication until the Hex dependency and consumer gates pass.
- **Next executor** — Jido Chat implementer, with the Jido Assembly maintainer for the consumer migration and the package maintainer for publication.

## Product Contract

### Summary

`jido_chat` owns the code, guides, and tests for all five providers. Host apps add only the dependencies for the provider features they use.

### Problem Frame

Each provider has its own release and maintenance work. All five inspected V3 revisions use the same Jido Chat adapter contract and a path dependency on the sibling core. Telegram appeared twice in the request. This plan counts it once.

### Actors

- Core-only users who install `jido_chat`.
- Provider users who select a default or custom transport, and hosts that start a Sensor.
- Package maintainers and the Jido Assembly maintainers.

### Requirements

- **R1** Move all five V3 adapter implementations into one Mix package under `Jido.Chat`. Preserve their V3 operations, module names, Signal contracts, and host-owned lifecycle.
- **R2** Make provider dependencies opt-in. The consolidated package adds zero required provider dependencies to the core-only consumer graph.
- **R3** Move the provider guides, examples, behavior tests, fixtures, and applicable contracts. Reuse existing core contracts and common test setup. Preserve provider-specific behavior tests.
- **R4** Give standalone package users a documented upgrade path. Prove the replacement in a published-package consumer before deprecating the standalone packages.

### Key Flows

- Outbound calls use a configured Client, a Chat or provider Action, a selected transport, and the existing completion or failure Signal.
- Inbound events use the provider normalizer and the existing delivery and Signal contracts. The host selects polling, push, webhook input, or another supported input mode.
- An upgrade replaces the standalone dependency with the consolidated package and the dependencies for the selected transport in the same change.

### Acceptance Examples

- A core-only app builds a production release and starts Chat without a provider connection or a provider-only dependency.
- A Telegram client can normalize a webhook update or send through an injected transport with ExGram absent. A default-transport call fails before any network request when ExGram is absent.
- An Assembly test host uses the consolidated Discord and Telegram adapters with local fixtures. It relays events through the same room in both directions without live credentials.

### Success Criteria

All five providers pass their recorded V3 parity checks. A clean consumer proves the dependency boundary. A second clean consumer exercises each documented provider configuration. The migration guide covers the package replacement and the released 1.x API differences.

### Scope Boundaries

The five named providers define the scope. Their V3 implementations define feature parity. Other providers, a redesign of the Chat Runtime or Jido dependency graph, and new provider features are outside this project.

### Key Decisions

Use one maintained package with optional provider dependencies. Use the consolidated V3 API as the published successor.

### Rejected Alternatives

Keeping five maintained packages would retain the release and maintenance work that the consolidation removes.

### Dependencies

The current core pins consolidated Jido V3. Assembly is the known active V3 consumer of Discord and Telegram. A compatible Jido release on Hex is required for the final packaging gate.

### Outstanding Questions

The package maintainer will select the first consolidated release and the retirement window. These choices control publication and retirement. The local move can start on the inspected V3 baseline.

### Sources

The direct request and the approved [Jido Chat and Assembly V3 goal brief](2026-11-16-1135-jido-chat-assembly-v3-goal-brief.md) establish the scope and integration consumer.

## Planning Contract

### Product Contract Preservation

This plan derives its requirements from the direct request. It uses the existing V3 provider contracts as the parity baseline.

### Current System

The table records the local source revisions inspected on 2026-11-21. Use these as provenance and recheck the branches before implementation.

| Package | Revision | Runtime boundary |
| --- | --- | --- |
| [`jido_chat`](../../mix.exs) | `release/v3` `c0e1cf3` | Client, native Actions and Signals, Sensor, optional Runtime. Application startup has no Chat process tree. |
| [`jido_chat_telegram`](https://github.com/agentjido/jido_chat_telegram/blob/2c1f08e15828fc32a85f06a0ff8eacc0993674e3/README.md) | `release/v3` `2c1f08e` | ExGram over Req, polling Source, pure webhook verification, 14 Telegram Actions. Operations also match an ExGram error struct. |
| [`jido_chat_discord`](https://github.com/agentjido/jido_chat_discord/blob/dad8f63dd93fc5e702f78c2e06796928487361ef/README.md) | `release/v3` `dad8f63` | Req REST, a Mint WebSocket Gateway, provider Actions, pure webhook handling, and a linked push Source worker. |
| [`jido_chat_slack`](https://github.com/agentjido/jido_chat_slack/blob/6a4927e205fa4fdcae3f4d62bc3970cc102c1364/README.md) | `main` `856d132` | Req Web API, signed webhooks, and an optional Socket Mode worker. The worker calls the Req socket API and uses a WebSockex client. |
| [`jido_chat_signal`](https://github.com/agentjido/jido_chat_signal/blob/e003b88bfb5e08fff1c0fbcb859d0e4e9dc73d43/README.md) | `release/v3` `e003b88` | Req JSON-RPC or the local `signal-cli` executable. A receive-only Source polls the selected transport. |
| [`jido_chat_x`](https://github.com/agentjido/jido_chat_x/blob/1f998d8f57e6ef63b149a54a0f97357b681c65a5/README.md) | `release/v3` `1f998d8` | XDK direct messages and host-delivered inbound events. The host supplies its XDK client in private options. |

The current `MIX_ENV=prod mix deps.tree --only prod --format plain` includes Req, Mint, and WebSockex through the required Jido and ReqLLM graph. The provider move is expected to leave that baseline graph intact. `mix hex.build` already rejects the Git dependency on `jido`. [Core manifest](../../mix.exs) · [V3 release evidence](2026-11-14-consolidated-v3-upgrade-result.md)

### Target System

The host continues to construct an immutable Client, select an adapter or Source, and execute the existing contract. `jido_chat` owns provider code below `lib/jido_chat/providers/<provider>/`. Store provider tests and fixtures below `test/jido_chat/providers/<provider>/` and public guides below `guides/providers/`. The source directory identifies provider ownership. The Elixir module names retain their existing V3 spelling.

| Feature | Host opt-in for built-in transport | Starting constraints for `jido_chat` |
| --- | --- | --- |
| Telegram Bot API and default polling | `:ex_gram`, `:req` | ExGram `~> 0.71.0`, Req `~> 0.7.1` |
| Discord REST and Gateway | Req for REST. Add Mint and Mint WebSocket for the default Gateway. | Shared Req, Mint `~> 1.8`, Mint WebSocket `~> 1.0.6` |
| Slack Web API and Socket Mode | Req for the Web API and opening a Socket Mode connection. Add WebSockex for the default socket client. | Shared Req, WebSockex `~> 0.5.1` |
| Signal Messenger | Req for the default JSON-RPC transport. The CLI transport needs a host-installed `signal-cli` executable. | Shared Req |
| X direct messages | `:xdk_elixir` | `~> 1.0` |

The starting constraints come from the adapter manifests and V3 lockfiles. All four Req-backed adapter checkouts resolve Req 0.7.5. Telegram locks ExGram 0.71.0. Use that line as the starting range because it includes rich-message casting and file upload fixes. Use one declaration per app with `optional: true`. Verify the lowest and locked versions that the combined graph can resolve before fixing the release constraints. [Telegram lockfile](https://github.com/agentjido/jido_chat_telegram/blob/2c1f08e15828fc32a85f06a0ff8eacc0993674e3/mix.lock) Jason is already required by core. Keep dotenv loading in the explicit developer or live-test workflow.

### Key Technical Decisions

- **KTD1 — Preserve module identity and provider boundaries.** Existing V3 module names, Signal types and schemas, resource references, and capability values are part of the compatibility contract. Leave `Jido.Chat.Signal` as the Signal Messenger facade. Core already owns descendants such as `Jido.Chat.Signal.Policy` and `Jido.Chat.Signal.MessageReceived`. The inspected sources have no duplicate fully qualified production definitions. Use the provider directory and the existing architecture test to enforce dependency direction. A Boundary on the `Jido.Chat.Signal` namespace would capture core modules. Renaming the facade would require changes in current callers. Governs R1 and U1–U5. [Architecture test](../../test/jido_chat/architecture_test.exs) · [Signal facade](https://github.com/agentjido/jido_chat_signal/blob/e003b88bfb5e08fff1c0fbcb859d0e4e9dc73d43/lib/jido_chat_signal.ex)
- **KTD2 — Put optionality at the transport and worker entry points.** Keep Client construction, catalogs, pure normalization, and injected paths usable in a core-only build. Isolate SDK struct expansion, remote types, behaviours, and macros inside the smallest transport implementation that needs them. Keep a callable entry point when a dependency is absent. Check missing deps before default I/O, stream consumption, or worker start. Preserve the existing typed `not_attempted` Action failure and use a safe missing-dependency reason at the transport or Source boundary. The public failure schema stays stable. An app-level on/off switch would also disable pure and injected paths. Governs R1, R2 and U1–U5. [Client](../../lib/jido_chat/client.ex) · [Action failure mapping](../../lib/jido_chat/operations/execution.ex)
- **KTD3 — Reuse core infrastructure and keep provider protocol logic local.** Use the core Adapter, Test Kit, Signals, Sensor, renderer helpers, package CI, and test entry point. Share an optional-dependency check or test helper only when it has the same contract in multiple providers. Keep HTTP serialization, error mapping, reconnect behavior, acknowledgements, webhook verification, and cursor logic in the owning provider. A common provider transport would add a new behavior contract to a packaging move. Governs R1, R3 and U1–U5. [Adapter Test Kit guide](../../guides/adapter_test_kit.md)
- **KTD4 — Replace each provider package atomically in the host.** The same modules exist in the standalone and consolidated packages. Remove the old dependency and lock entry as the host adds the new package and opt-ins. Maintain a version-specific migration guide and use existing 1.x releases for legacy hosts during the transition. A new forwarding package would extend the old release work and offers little value when V3 module names already match. Governs R4 and U6–U7. [Assembly manifest](https://github.com/agentjido/jido_showcase/blob/ce3f1dc17a312f15eabbaaae44b238057f176b90/jido_assembly/mix.exs)

### System Boundaries and Change Surface

| Surface | Planned change | Invariant or risk to check |
| --- | --- | --- |
| Dependency resolution and build | Edit one `mix.exs`, lock, and CI. Compile pure provider modules in the base build. Isolate dependency-specific definitions and verify add/remove opt-ins in the same host as well as clean builds. | A full local package build can mask missing deps. Cached BEAMs can mask a broken enable or disable path. No new required dependency closure or unrelated version overrides. |
| Core and provider modules | Add provider files and extend the architecture check to permit provider-to-core and provider-to-Sensor calls. Keep core and Runtime generic. | `Jido.Chat.Signal.*` core definitions must stay owned by core. Each provider module loads from a single `:jido_chat` BEAM path. |
| Lifecycle and secrets | Keep Source and worker startup explicit. Preserve Discord resume and heartbeat behavior, Slack acknowledgement after admission, and Telegram and Signal cursor rules. Keep tokens, signing secrets, and SDK clients in existing private fields. | No implicit network or provider worker at Chat start. No credential in Signals or missing-dependency errors. No persistent record rewrite or replay policy change. |
| Documentation and evidence | Merge provider README material and guides into the core docs index. Keep unique scenarios, fixtures, provider examples, usage rules, and attribution. Use one ExUnit setup and a common `:live` exclusion. | Keep Covenant obligations under `test/contracts/<app>/` at the depth its loader expects. Keep existing obligation IDs, component coverage, and matching fixtures. Place contract test files under the existing recursive test glob. Regenerate coverage manifests with Covenant. [Contract guide](../../test/contracts/README.md) |
| Consumer migration | Change the Assembly V3 checkout of Showcase. Check the released 1.x configuration in the main checkout of the same repo and cover it in the upgrade guide. Update ecosystem package pages and workspace references at deprecation. | The retired Jido Messaging demo still refers to Discord and Telegram. Record it as a legacy consumer and keep its historical dependency pins. Verify current public reverse dependencies again before notices. |

### Implementation Units

#### U1 — Telegram and the first optional transport

- **Dependencies** — None. **Requirements** — R1, R2, R3.
- **Result and surfaces** — Move the [Telegram library](https://github.com/agentjido/jido_chat_telegram/tree/2c1f08e15828fc32a85f06a0ff8eacc0993674e3/lib), its guides, two examples, tests, and Covenant contracts. Establish the provider directory, shared test setup, and first minimal and opt-in consumer checks. Isolate the `ExGram.Error` match in Operations along with the ExGram adapter and model references. Use the existing Req-backed ExGram path. Preserve rate-limit hints, upload/download behavior, and source ownership.
- **Proof and handoff** — Run the migrated fixture and contract suites. In a fresh core-only consumer, prove no ExGram and successful webhook normalization and an injected send. Prove a default call fails before consuming a stream or making a request. With Telegram enabled, exercise the default transport against the local HTTP server. Complete Gates V1, V2, and V3 for Telegram.

#### U2 — Discord REST and Gateway

- **Dependencies** — U1. **Requirements** — R1, R2, R3.
- **Result and surfaces** — Move the [Discord library](https://github.com/agentjido/jido_chat_discord/tree/dad8f63dd93fc5e702f78c2e06796928487361ef/lib), Gateway tests, fixtures, guides, and Covenant obligations. Keep REST and Gateway opt-ins distinct. Check for the selected Gateway transport before outbound discovery or worker startup. Preserve injected Gateway and REST clients.
- **Proof and handoff** — Exercise REST-only operation, a missing Gateway dependency with no worker or HTTP request, and a real default Gateway implementation against the local WebSocket peer. Re-run webhook, input admission, heartbeat, reconnect, and resume fixtures. Complete Gates V1, V2, and V3 for Discord.

#### U3 — Slack Web API, webhooks, and Socket Mode

- **Dependencies** — U1. **Requirements** — R1, R2, R3.
- **Result and surfaces** — Move the [Slack library](https://github.com/agentjido/jido_chat_slack/tree/6a4927e205fa4fdcae3f4d62bc3970cc102c1364/lib), README and architecture material, and tests. Isolate the `use WebSockex` module. Check the selected socket and open clients before worker startup. Keep signed webhook verification and decoding usable without the socket client.
- **Proof and handoff** — Cover Web API and three-step uploads, webhook verification and normalization, and Socket Mode acknowledgement after successful Sensor admission. Exercise the missing default socket path and assert that the opening client receives zero requests. Verify the injected socket and API clients. Complete Gates V1, V2, and V3 for Slack.

#### U4 — Signal Messenger JSON-RPC and CLI

- **Dependencies** — U1. **Requirements** — R1, R2, R3.
- **Result and surfaces** — Move the [Signal Messenger library](https://github.com/agentjido/jido_chat_signal/tree/e003b88bfb5e08fff1c0fbcb859d0e4e9dc73d43/lib) to the provider directory with its facade and public descendants intact. Keep the CLI transport free of Req calls. Create a provider guide from the README and retain the source, CLI, and Adapter Test Kit cases.
- **Proof and handoff** — Compile the canonical Signals and the provider together. Exercise JSON-RPC with a local endpoint or Req test adapter, CLI send and polling with the temporary shell fixture, and missing JSON-RPC transport behavior. Check attachment cleanup and polling cursor and source identity behavior. Complete Gates V1, V2, and V3 for Signal Messenger.

#### U5 — X direct messages

- **Dependencies** — U1. **Requirements** — R1, R2, R3.
- **Result and surfaces** — Move the [X library](https://github.com/agentjido/jido_chat_x/tree/1f998d8f57e6ef63b149a54a0f97357b681c65a5/lib), README material, inbound fixtures, and Adapter Test Kit cases. Keep the XDK dependency behind the default transport. Preserve the private XDK client option, custom transport, and host ownership of the Finch pool.
- **Proof and handoff** — Exercise missing XDK and successful injected calls without XDK. With XDK selected, start a host-supervised Finch pool through `Xdk.child_spec/1`. Use `Xdk.new(finch: pool_name, base_url: local_url)` to exercise a default transport operation against a local endpoint. Exercise normalized DM events and fetch pagination fixtures. Complete Gates V1, V2, and V3 for X.

#### U6 — Assembly V3 consumer and upgrade guide

- **Dependencies** — U2, U3, U4, U5. **Requirements** — R3, R4.
- **Result and surfaces** — Remove both standalone deps from [Assembly V3](https://github.com/agentjido/jido_showcase/blob/ce3f1dc17a312f15eabbaaae44b238057f176b90/jido_assembly/mix.exs) in one change. Add only the documented Discord and Telegram transport dependencies the application uses. Refresh its lock and guide. Add one core migration guide covering 1.x and V3 source consumers for all five, including credentials, host-owned ingress, and any provider-specific legacy API changes. Update the core README and docs index. Inventory ecosystem and legacy references for publication. Compare each guide against the latest standalone 1.x release tag and the inspected V3 source. Add an offline Assembly integration case that activates the provider bindings with fixture credentials and injected transports. The existing demo keeps its bindings disabled. [Assembly bridge tests](https://github.com/agentjido/jido_showcase/blob/ce3f1dc17a312f15eabbaaae44b238057f176b90/jido_assembly/test/jido_assembly/bridges_test.exs)
- **Proof and handoff** — Run Gate V4. Verify docs examples resolve against the consolidated package and that no selected module loads from a standalone package.

#### U7 — Release candidate and deprecation evidence

- **Dependencies** — U6. **Requirements** — R2, R3, R4.
- **Result and surfaces** — Use a compatible published Jido V3 dependency. Run the release CI checks and build a Hex archive. Inspect the published file list and optional dependency metadata. Verify the five consumer installs against the package artifact. Prepare deprecation links for all five repos and the ecosystem pages.
- **Proof and handoff** — Pass Gates V1–V5 with the release dependency inputs. Record the exact artifact, release dependency graph, consumers verified, and remaining publication decisions. After authorized publication, repeat package resolution and smoke checks against Hex before any retirement action.

### Work Graph

U1 is the first unit. U2–U5 can proceed after it establishes the optional transport and test conventions. Integrate changes to the shared manifest, lock, test helper, and documentation index one at a time. U6 integrates the provider results with the consumer migration. U7 proves the combined archive and gives the release owner the evidence for retirement. The Jido Hex dependency is a prerequisite for U7.

### Verification Contract

Run the following checks from `jido_chat` or the consumer root shown in the table. Capture the package and toolchain revisions with the results. All provider smoke checks use local fixtures or injected transports. Live tests require a separate decision.

| Gate | Where and how | Pass evidence |
| --- | --- | --- |
| V1 Provider parity | `jido_chat`. Run `mix test` for each moved provider directory and matching tests under `test/contracts`. Run `mix test.contracts` for the full obligation set. Compare the results with the inspected V3 suites. | Each provider preserves its tested behavior, API, wire shapes, validation, and worker lifecycle. Every omitted test has a documented equivalent. |
| V2 Minimal consumer | Fresh downstream Mix project with only `jido_chat` as its direct dependency. Run `MIX_ENV=prod mix deps.tree --only prod --format plain`, `MIX_ENV=prod mix compile --warnings-as-errors`, and `MIX_ENV=prod mix release`. Boot the release. Also run `MIX_ENV=prod mix compile --no-optional-deps --warnings-as-errors` from a clean build of `jido_chat`. | Compare the resolved app closure with the pre-move V3 baseline under the same resolver inputs. ExGram, Mint WebSocket, XDK, and their unique transitive dependencies are absent. Provider modules have one owner. Pure operations and custom transports still work. No provider process or I/O starts at application boot. |
| V3 Provider opt-in and failure | Fresh downstream consumer for each documented configuration. Use the same compile and release checks as V2 plus one default transport smoke test for each documented feature. Exercise the lowest supported dependency resolution and the normal lock. Narrow a version constraint when a lower version fails a required scenario. Run add/remove dependency smoke checks with the same build directory. Force availability cases through an isolated test seam for Req, Mint, or WebSockex if the Jido graph already includes them. | Selected transport and Source work with the documented deps. Unselected provider-only apps stay absent. Missing required pieces fail before I/O, worker startup, or input consumption. The selected transport reflects the current dependency availability after an opt-in change. |
| V4 Assembly | `jido_showcase/jido_assembly`. Run `mix test test/jido_assembly/bridges_test.exs` and `mix test`. Run the new offline Assembly bridge case with real adapters and a shared Room. Inject each provider event and record the outbound request at the other transport. | Discord and Telegram carry events through the same room. Assembly resolves each provider module from `:jido_chat`. Its graph has neither standalone package. |
| V5 Package | `jido_chat`. Run `mix quality`, `mix test`, `mix test.contracts`, `mix coveralls`, `mix docs -f html -f markdown`, and `MIX_ENV=prod mix hex.build`. Unpack the built archive and run the consumer matrix using its contents. After publication, repeat the matrix with the Hex release. | The current quality and coverage gates pass. Covenant recognizes both migrated contract sets. The archive contains provider source and guides and marks all new provider dependencies optional. The Hex consumer resolves without paths, Git dependencies, or private configuration. |

| Requirement | Units | Verification |
| --- | --- | --- |
| R1 | U1, U2, U3, U4, U5 | V1, V3, V4 |
| R2 | U1, U2, U3, U4, U5, U7 | V2, V3, V5 |
| R3 | U1, U2, U3, U4, U5, U6, U7 | V1, V4, V5 |
| R4 | U6, U7 | V4, V5 |

### Rollout and Recovery

1. Finish the local provider units and Assembly integration. Keep one viable standalone release per provider for existing hosts. The release notes and guide must identify the V3 replacement and the same-change dependency switch.
2. With release authority, publish the consolidated `jido_chat` release first. Install it from Hex, verify the minimal and provider consumer checks, and verify the supported Assembly migration. Stop the rollout on a dependency regression, duplicate module, lost provider behavior, or startup side effect.
3. With deprecation authority, update the five repo notices and ecosystem entries, and retire selected Hex versions with a link to the replacement guide. Hex retirement warns users and leaves old artifacts resolvable. Archival is a separate repository decision. [Hex retirement](https://hex.hexdocs.pm/Mix.Tasks.Hex.Retire.html)
4. If a consumer upgrade fails, stop its provider workers and restore the previous complete manifest and lock as a pair. Re-run that consumer's bridge or delivery check. Use its existing offset and replay rules. Keep only one active receiver per bot or account where the current provider requires it. Hold retirement until the replacement passes again.

### Risks and Assumptions

- **Transitive dependency masking** — Req, Mint, and WebSockex may resolve in a core-only host today. The dependency closure comparison and explicit missing-dependency checks prove different conditions. Both are required.
- **Namespace overlap** — The Signal Messenger facade and the canonical Signal definitions share a prefix. Preserve their tested exports and verify dependency direction by source ownership.
- **Covenant discovery** — The loader rejects obligation files at the wrong depth. A wrong test or fixture path can also remove coverage. Check discovered obligations and matching results against both current sets.
- **Downstream visibility** — Hex lists zero published dependants for the five packages at planning time. Local Assembly depends on two of them. External host apps are unverified. [Discord](https://hex.pm/packages/jido_chat_discord/dependents) · [Telegram](https://hex.pm/packages/jido_chat_telegram/dependents) · [Slack](https://hex.pm/packages/jido_chat_slack/dependents) · [Signal](https://hex.pm/packages/jido_chat_signal/dependents) · [X](https://hex.pm/packages/jido_chat_x/dependents)
- **Build size** — The base package includes some provider BEAMs and source. The measurable promise is zero added required packages. Record the release size delta to make the bundled code cost visible.
- **Baseline evidence** — The source and dependency graph were checked for this plan. Provider parity, consumer, and live behavior checks apply to a later implementation.

### Open Planning Decisions

- **Release gate** — The package maintainer must select a published Jido V3 version and prove compatibility before U7 can finish. Test `3.0.0-beta.3` first if the maintainer accepts a prerelease dependency. The local tag descends from the current Git pin. The full suite and new consumer checks must establish compatibility. [Jido beta.3 package](https://hex.pm/packages/jido/3.0.0-beta.3/files/README.md?fallback=default)
- **Deferred release decisions** — The package maintainer owns the publication date, supported 1.x transition window, and retirement versions. The repository owner controls any archive action.

### Definition of Done

The five adapters have one source of truth in `jido_chat`. The release candidate passes V1–V5, including zero added required provider dependencies for a core-only install. Each provider passes its opt-in and missing-dependency checks. Assembly passes on the replacement. The core guides describe every install mode and migration. Package maintainers have the exact verification evidence and the five replacement links required to deprecate the old packages after authorized publication.

### Planning Sources

- [Core adapter contract](../../lib/jido_chat/adapter.ex) · [Core architecture rules](../../AGENTS.md) · [Source layout](../../guides/source_layout.md) · [CI gates](../../.github/workflows/ci.yml)
- [Discord validation](https://github.com/agentjido/jido_chat_discord/blob/dad8f63dd93fc5e702f78c2e06796928487361ef/docs/v3-upgrade-validation.md) · [Telegram validation](https://github.com/agentjido/jido_chat_telegram/blob/2c1f08e15828fc32a85f06a0ff8eacc0993674e3/docs/v3-upgrade-validation.md) · [Slack validation](https://github.com/agentjido/jido_chat_slack/blob/6a4927e205fa4fdcae3f4d62bc3970cc102c1364/docs/validation.md) · [Signal validation](https://github.com/agentjido/jido_chat_signal/blob/e003b88bfb5e08fff1c0fbcb859d0e4e9dc73d43/docs/v3-upgrade-validation.md) · [X validation](https://github.com/agentjido/jido_chat_x/blob/1f998d8f57e6ef63b149a54a0f97357b681c65a5/docs/v3-upgrade-validation.md)
- [Mix optional dependencies and compile check](https://mix.hexdocs.pm/1.18.4/Mix.Tasks.Deps.html#module-dependency-definition-options) · [Hex build requirements](https://hex.hexdocs.pm/Mix.Tasks.Hex.Build.html#module-dependencies)

## Adapter Results

- **Markdown** — Canonical plan in this file.
- **HTML and Beadwork** — No output requested.
