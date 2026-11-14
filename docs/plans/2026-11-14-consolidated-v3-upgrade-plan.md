---
title: Upgrade Chat to consolidated Jido V3
date: 2026-11-14
assignment: U2
status: checked-source-plan
implementation_readiness: conditional
---

# Upgrade Chat to consolidated Jido V3

This plan covers `agentjido/jido_chat`. The Jido workspace chat owns integration.
This audit did not change code, manifests, locks, branches, or external systems.
It did not install dependencies, compile code, or run tests. The commands below
are future checks, not passing results.

## Source record

The following state was recorded before this plan was written:

| Item | Observed value |
| --- | --- |
| Repository | `/Users/mhostetler/Source/Jido/jido_chat/jido_chat` |
| Origin | `git@github.com:agentjido/jido_chat.git` |
| Branch | `release/v3` |
| HEAD | `1cae095d67c5e0e0592ec801c1714fbdcac9fa57` |
| Local changes | None; `git status --porcelain=v1` was empty |
| GitHub `release/v3` | `1cae095d67c5e0e0592ec801c1714fbdcac9fa57`, read with `gh api` |
| Required core | `agentjido/jido`, `release/v3`, exact revision `05723b96c6ead47dec04fe69b1c34ad62f999c54` |

Use the existing Chat `release/v3` branch at that exact Chat HEAD as the
implementation baseline. If a separate work branch is required, create it from
that commit after implementation is authorized. Do not start from `main`.
HEAD already includes the runtime alignment change, the removal of
`SignalAction`, and static room Signal dispatch. There is no local `main` branch.
No branch switch or branch creation was done.

Instructions read: workspace `AGENTS.md` and repository `AGENTS.md`. There is no
repository `docs/ROLE.md`. The group folder is not a Git repository.

Core source was read from a GitHub archive at the exact required revision. The
archive was extracted under `/tmp/u2-jido-target` for inspection only. The older
workspace Jido checkout was not used as target evidence. Network access through
the default sandbox failed; the approved read-only `gh api` request succeeded.

## Compatibility boundary

This is a breaking consumer migration to one consolidated `:jido` application.
The final graph must not contain `:jido_action`, `:jido_signal`, or `:jido_ai`.
Do not copy core modules into Chat. Keep the current SDK, Integration, and
Runtime ownership. Chat application startup must still start no Chat process,
Sensor, storage resource, queue, or room.

The target manifest declares Jido `3.0.0-beta.2`, Zoi `~> 0.19.0`, ReqLLM
`~> 1.30`, and Runic `~> 0.1.0-alpha.13`. The Chat lock still selects Jido
`e783fe1b4d19e797819e9a0569b16866f83825a6`, Action
`177e7a4ce4342a9a6b7bc668f540dafbd7169d54`, Signal `3.0.0-beta.5`, Zoi
`0.18.11`, and Runic Git main at `0c15a9c107137b8c13ebbc3340abd207d8f1f3ff`.

## Required changes and source evidence

All Chat paths below are relative to this repository. Core paths refer to the
exact target revision linked in the source list.

| Files | Required change and evidence |
| --- | --- |
| `mix.exs`, `mix.lock` | Remove split Action and Signal dependencies. Pin the single Jido dependency to the exact target for this migration. Raise Zoi to `~> 0.19.0`. Remove the Runic Git-main override: Chat has no direct Runic calls; core must select its supported Runic source. Resolve the new ReqLLM dependencies through core. Regenerate the lock from Mix; do not edit hashes by hand. |
| `mix.exs`, `test/test_helper.exs`, `lib/jido_chat.ex`, `guides/static_sdk.md` | Resolve startup ownership explicitly. The target `Jido.Exec.run/4` runs work under `Jido.Exec.TaskSupervisor`, which `Jido.Application` starts. Chat currently declares Jido with `runtime: false`; plain SDK tests do not all start Jido. Recommend a normal runtime Jido dependency, with no automatic Jido instance or Chat resource. Test SDK execution from a normal application start. If the package must retain `runtime: false`, document and test explicit host startup before SDK execution; do not start core processes inside Chat. |
| `lib/jido_chat.ex` | Replace the absent `%Jido.Action.Error.TimeoutError{}` match with the target timeout error contract (`Jido.Error.TimeoutError`; verify the actual Exec timeout path). Preserve one provider attempt and the unknown-outcome Chat failure. `Jido.Exec.run/4` still supports synchronous Action results; it is not the AgentServer Turn API. |
| `lib/jido_chat/runtime/{resources,room,participant,connection,bridge}.ex`, `runtime/bridge/mapping.ex`, `runtime/room/plugin.ex`, `runtime/signal/room.ex` | Replace absent `Jido.Agent.Ref` types, schemas, validators, and struct matches with `Jido.Agent.Address`. Replace absent `Jido.agent_ref/3` with `Jido.agent_address/3`. Both identity fields and partition checks must stay exact. Target `agent/address.ex` permits a nonempty string partition or nil. |
| `runtime/resources.ex`, `runtime/bridge.ex` | Remove calls to absent `Jido.namespace/1`. Build the expected address with `Jido.agent_address/3`, then compare the full address, including namespace and partition, or compare the returned namespace where only that check is intended. Do not use private NamespaceRegistry calls as a public replacement. |
| `runtime/connection.ex`, runtime test setup, `guides/runtime.md` | Replace absent `Jido.start_agent_ref/3` and `Jido.stop_agent_ref/2`. For a new memory account, use `Jido.start_agent/3` with the instantiated Agent and the address partition. Use `Jido.stop_agent/3` with the resolved worker and partition. Do not substitute durable `create_agent/4` plus `activate_agent/3` without a lifecycle decision. Core `activate_agent/3` only activates an existing durable record. Preserve duplicate-account rejection and host ownership. |
| `runtime/{participant,bridge}.ex`, `runtime/bridge/worker.ex`, `test/jido_chat/{plugin,create_thread_agent,runtime_room,runtime_bridge}_test.exs` | Replace old `{:ok, agent, directives}` Agent call matches. Core `Jido.call/4` and `Jido.AgentServer.call/3` return `{:ok, %Jido.AgentServer.TurnResult{}}`. A successful transport does not prove a committed turn. Check `status`, `error`, and required effects or replies. A committed turn can still have pending effects. Preserve Bridge submitted/unknown/completed distinctions. |
| `runtime/{participant,bridge}.ex`, runtime tests | Membership and retained-message checks currently read `agent.state.room` from a call result. Target results do not carry Agent state. Proposed minimum: require a committed CheckMember turn, resolve the room worker, read public `Jido.AgentServer.snapshot/2`, validate its full address and use `snapshot.agent.state.room`. Check retained Signal ID and data as before. Snapshot is a later read, not the same-turn state; test concurrent leave, eviction, and activation replacement. Do not weaken admission. If same-turn proof is required, stop for a contract decision: a typed room reply through `Jido.Agent.Directive.reply/1` is supported but changes the Chat room protocol. |
| `lib/jido_chat/plugin.ex`, `plugin/{execute,deliver,ingress,runtime}.ex`, `runtime/{room/plugin,participant,bridge,actions/*}.ex` | Keep the current extension and Plugin architecture. Target `Jido.Agent.Extension` retains `lower/2`, `normalize/1`, and `verify/2`; `Jido.Plugin` retains prepare, admit, reduce, child specification, readiness, directives, and dispatch callbacks. Target Init retains Agent server, ID, Jido, partition, module, and options. Target admission/reduction inputs retain the fields Chat uses. Verify action context and post-commit dispatch with focused tests. `Jido.whereis_agent/3` still supports the current partition-aware result return. |
| `lib/jido_chat_action.ex`, `lib/jido_chat_action/execution.ex`, `lib/jido_chat/signal/**`, model and rendering files | Check all schemas and struct macros under Zoi 0.19. Target `Jido.Joi` explicitly states that its schemas are ordinary Zoi schemas; a complete namespace rewrite to Joi is not required. Target Signal retains `__compile_definition__/2`, `__normalize_definition_attrs__/2`, definition constructors, Catalog, context, and trace APIs. Test these internal macro calls because Chat uses them directly. Preserve data keys, schema identities, defaults, JSON restrictions, and causal context. |
| `runtime/storage.ex`, `runtime/storage/{history,rooms,links,outbox,commit,memory}.ex` | Keep these Chat-owned capability callbacks. They are not `Jido.Persistence` callbacks. Preserve history order, atomic commit, link identity, outbox compare-and-set transitions, and host resource ownership. Address-bearing member values need consumer codec checks before delivery. No database or data conversion is part of U2. |
| `test/contracts/**`, relevant guides and public API fixtures | Keep the adapter and static SDK contracts. Update only approved, intentional contract differences. Do not regenerate all fixtures to hide failures. Update old Ref/start/call examples in `guides/runtime.md` and `guides/architecture.md`. |

## Unit order

1. Freeze source records and the shared target. Check the worktree again.
2. Change the manifest and resolve the single-core graph in an isolated build.
3. Repair Zoi compilation and the removed timeout error type. Establish core
   application startup for SDK execution. Run Signal and Action contracts.
4. Migrate runtime identities and lifecycle calls. Keep account IDs, room bus
   identity tuples, and bridge durable-ID inputs stable in meaning.
5. Migrate TurnResult handling and admission reads. Run Plugin and runtime tests.
6. Run storage and contract checks. Check the Jidoka member codec with U5.
7. Run full package checks, then repeat in a portable source graph. Return exact
   candidate revision and lock evidence to U5. U5 owns the combined application.

U2 has no dependency on U1, U3, or U4 for package implementation. Final U5
integration depends on a checked U2 candidate. Release order, if later authorized:
consolidated Jido, then Chat, then required adapter consumers, then Jidoka.

## Source and lock strategy

For local development, use a separate Jido source tree at the exact target.
Before any path test, confirm its HEAD and clean state. Do not point at the older
workspace Jido tree. A temporary Chat `path:` dependency can use that source;
keep that wiring out of delivery. Keep the path-test lock separate from the
portable candidate lock, and use fresh build/dependency directories so old split
modules cannot remain in compile paths.

For portable verification, use
`{:jido, github: "agentjido/jido", ref: "05723b96c6ead47dec04fe69b1c34ad62f999c54"}`.
Use normal runtime startup as recommended above. Do not add split-core overrides.
Use the registry Runic constraint selected by core. Use `mix deps.get` after the
manifest edit; if Mix requests an explicit unlock, unlock only removed or changed
sources and their required constraints. Do not use `mix deps.update --all`.
Record the resolved Runic, Zoi, and ReqLLM versions. Check `mix deps.tree` and
`mix.lock` for absent split applications and one core source. Check generated
application dependency metadata and loaded module paths too; a lock alone does
not prove unique module ownership.

Repeat the gates in a clean temporary copy that has no sibling path dependencies
or old `_build`/`deps`. Its manifest and lock must select the same exact core
revision. A successful local path build does not prove portable resolution.
For final Hex delivery, select a published consolidated release only after it
contains these APIs and rerun checks. A beta version string alone is insufficient.

## Exact future checks

Run from this repository after implementation and dependency resolution.
Elixir `~> 1.18` is declared. `mix` and `elixir` shims exist; toolchain versions
and native Markdown build support were not tested. No model, provider, database,
or live service is required for the following Chat checks.

```sh
mix deps.get
mix deps.tree
mix compile --warnings-as-errors
MIX_ENV=test mix compile --warnings-as-errors
mix test test/jido_chat/v3_baseline_test.exs test/jido_chat/public_signal_contract_test.exs test/jido_chat/signal_boundary_test.exs test/jido_chat/delivery_signal_test.exs test/jido_chat/chat_action_test.exs
mix test test/jido_chat/plugin_test.exs test/jido_chat/plugin_config_test.exs test/jido_chat/plugin_patterns_test.exs test/jido_chat/create_thread_agent_test.exs test/jido_chat/sensor_test.exs test/jido_chat/push_sensor_test.exs
mix test test/jido_chat/runtime_room_test.exs test/jido_chat/runtime_bridge_test.exs test/jido_chat/runtime_storage_test.exs test/jido_chat/architecture_test.exs test/jido_chat/domain_boundaries_test.exs
mix test test/contracts
mix test.contracts
mix test
mix quality
mix coveralls
MIX_ENV=prod mix hex.build
mix docs -f html -f markdown
git diff --check
git status --short
```

`mix test.contracts` is the alias for `covenant.check`; it is not a replacement
for `mix test test/contracts`. `mix quality` selects test environment and runs
format check, warnings-as-errors compile, strict Credo, Dialyzer, and Doctor.
It does not run the test suite. `mix coveralls` has a declared 90 percent
threshold. The CI caller uses the shared v5 workflow, package build, Docs,
`mix test`, and `mix test.contracts`. Do not install hooks or use `mix setup`
during this planning phase. Record actual exit codes during implementation.

Add focused cases for: memory startup and stop by Address; cross-namespace and
cross-partition rejection; SDK call after ordinary app startup; Exec timeout;
committed and failed TurnResults; effects still pending after commit; no duplicate
provider call; room leave and history eviction during admission; account restart
and outbox recovery; unchanged storage commit and state-transition behavior.

## Direct consumers and coverage limits

Only source inspection was done. No consumer was compiled or tested.

| Consumer | Observed dependency or interface | Required follow-up |
| --- | --- | --- |
| Jidoka | Local Chat path is invalid in its manifest. `lib/jidoka/chat/runtime.ex` uses Chat Runtime. `lib/jidoka/chat/storage.ex` implements History, Rooms, Commit and stores Agent members as `{"kind": "agent", "ref": Ref.to_map!(ref)}`; decode uses `Ref.from_map!/1`. | U5 repairs its path and calls. Compare old and new versioned identity maps with fixed fixtures. Preserve stored meaning and keys. Stop if conversion is required. U2 does not edit Jidoka. |
| Telegram, Discord, Slack, GitHub, Signal adapters | Manifests select Chat ref `0b6f16d9b91b37c61f2ad913dcdd4adea1713f88` with local path options. Telegram, Discord, and Slack define `Jido.ChatAction` extensions. | If the Action or Signal contract changes, run mocked extension construction and execution checks in affected consumers. No adapter migration is required solely to rename internal runtime identities. |
| Mattermost | Manifest selects Chat `~> 1.2 and >= 1.2.1`. | Outside this V3 migration. No compatibility claim. |
| Teams, WhatsApp, X | Present as sibling adapters; no full interface audit. | Untested and outside the required application graph unless U5 proves use. |
| `jido_messaging` | Uses sibling Chat, split core dependencies, old Zoi, old Ref APIs, and delegates Chat Plugin callbacks. | Affected direct consumer. Its separate room/runtime code requires its own migration if used. Do not copy it into Chat or expand U2 to this package. |

No public adapter operation change is required by the inspected source. The
runtime identity type and Agent call result are public breaking changes. Keep
the adapter SDK stable if possible. If implementation changes `Jido.ChatAction`,
Signal schema identity, or adapter callbacks, report the exact affected adapters
and perform focused checks before claiming that contract is checked.

## Blockers and readiness

The source audit and plan are complete. Dependency-only implementation is not
sufficient. Runtime API changes are required.

The target has replacements for identity, activation, snapshots, and replies;
no core code change is justified by this audit. There is no direct equivalent
of the old Ref startup wrapper or old call result containing Agent state.
Use the public APIs named above. Do not add compatibility modules to Chat.

Implementation can start after the coordinator authorizes the next phase.
Delivery remains conditional on three checks: the admission snapshot must
preserve the required room checks; the new core startup requirement must be
explicit; and U5 must prove that the member codec preserves existing stored
meaning. If a typed same-turn room reply or a stored-data conversion is needed,
stop that unit and return the exact contract decision. No such change is
preauthorized. Compilation, runtime compatibility, lock resolution, and adapter
compatibility remain unproved.

## Sources

- [Coordinator plan](../../../../docs/plans/2026-11-14-0821-jidoka-consolidated-v3-plan.md)
- [Package instructions](../../AGENTS.md)
- [Manifest](../../mix.exs), [lock](../../mix.lock), and [CI caller](../../.github/workflows/ci.yml)
- [Chat Plugin](../../lib/jido_chat/plugin.ex) and [runtime connection](../../lib/jido_chat/runtime/connection.ex)
- [Runtime Bridge](../../lib/jido_chat/runtime/bridge.ex) and [worker](../../lib/jido_chat/runtime/bridge/worker.ex)
- [Storage contracts](../../lib/jido_chat/runtime/storage.ex)
- [Action macro](../../lib/jido_chat_action.ex) and [Signal policy](../../lib/jido_chat/signal/policy.ex)
- [Exact target tree](https://github.com/agentjido/jido/tree/05723b96c6ead47dec04fe69b1c34ad62f999c54)
- [Target instance APIs](https://github.com/agentjido/jido/blob/05723b96c6ead47dec04fe69b1c34ad62f999c54/lib/jido.ex)
- [Target Address](https://github.com/agentjido/jido/blob/05723b96c6ead47dec04fe69b1c34ad62f999c54/lib/jido/agent/address.ex)
- [Target TurnResult](https://github.com/agentjido/jido/blob/05723b96c6ead47dec04fe69b1c34ad62f999c54/lib/jido/agent_server/turn_result.ex)
- [Target Plugin](https://github.com/agentjido/jido/blob/05723b96c6ead47dec04fe69b1c34ad62f999c54/lib/jido/plugin.ex)
- [Target Joi schema contract](https://github.com/agentjido/jido/blob/05723b96c6ead47dec04fe69b1c34ad62f999c54/lib/jido/joi.ex)
