---
title: Consolidated Jido V3 baseline
type: implementation-plan
date: 2026-11-16
last_reviewed: 2026-11-16
artifact_contract: kata-plan/v1
artifact_readiness: complete
domain: software
execution: code
product_contract_source: direct-request
---

# Consolidated Jido V3 Baseline

## Goal Capsule

- Objective: Jido Chat uses one reviewed consolidated Jido V3 source and no split schema package, and the exact source is recorded for the later Assembly cutover.
- Means: Gate the current V3 head, move Jido Chat schemas to `Jido.Joi`, remove direct Zoi use, and prove the package contracts.
- Authority: Local changes and checks in the Jido Chat workspace. No commit, push, release, publication, or remote retirement.
- Stop conditions: Stop before a destructive data change, a provider call that needs a credential, or a product-contract change.
- Next executor: Elixir package engineer.

## Product Contract

### Summary

Establish one Jido V3 foundation before new runtime, storage, adapter, or Assembly UI work starts.

### Problem Frame

Jido Chat pins an older consolidated Jido V3 commit and calls Zoi directly. Jido Assembly still uses the standalone `jido_ai` package and its V2 Agent helpers. This split makes later Chat runtime and Assembly work depend on two schema and Agent contracts.

### Actors

- A Jido Chat maintainer selects and verifies the consolidated dependency.
- Jido Chat consumers use the same public Chat data and Signal contracts after the schema-boundary change.
- Jido Assembly uses the consolidated Agent and AI runtime for its Bridge, Runbook, and Triage personas.

### Requirements

- **R1:** Jido Chat selects the exact consolidated Jido V3 commit that Assembly will use at its atomic V3 cutover.
- **R2:** Jido Chat uses `Jido.Joi` as its schema boundary and has no direct `Zoi.*` call in production or test source.
- **R3:** Existing public Chat value, Signal, Action, Agent, and Runtime validation behavior stays stable, including defaults, null values, ranges, closed external fields, stored values, and portable JSON data.
- **R4:** Jido Chat does not declare Zoi directly after all direct use is removed. It keeps direct Spark and Splode dependencies because its source calls their public modules.
- **R5:** Deferred to goal Unit 5: Jido Assembly has no `jido_ai` dependency or `config :jido_ai` entry after its V3 backend cutover.
- **R6:** Deferred to goal Unit 5: Assembly declares every package API that it calls directly and does not depend on a transitive `ReqLLM` contract.
- **R7:** Focused tests, full Jido Chat package checks, and an Elixir design review prove the baseline before Unit 1 starts.

### Key Flows

Jido Chat schema flow:

```text
external map -> closed Jido.Joi parse -> typed Signal or value -> portable stored or wire value
```

Assembly agent flow:

```text
room command -> Assembly persona selection -> consolidated Jido AI turn -> chat-sized text -> durable message
```

### Acceptance Examples

- An undeclared field in a public Chat Signal is rejected.
- A valid card, modal, message, Room record, and Agent state keep their current defaults and survive a JSON round trip.
- A nullable optional field accepts a missing key and `nil`; a required nullable field accepts `nil` but not a missing key.
- A lower-bound integer still rejects a value below its bound.
- `rg` finds no direct `Zoi` reference in Jido Chat production or test source.
- Jido Chat resolves the selected Jido commit and passes its repository gates.
- Dependency resolution proves that the Assembly cutover must remove `jido_messaging` and the V2 adapters in the same later migration slice.

### Success Criteria

- Requirements R1 through R4 and R7 pass their named verification gates. R5 and R6 remain assigned to goal Unit 5.
- The selected consolidated commit is recorded in the Jido Chat manifest and the goal brief for the later Assembly cutover.
- No supported public Chat contract changes without a regression test and explicit plan update.

### Scope Boundaries

Included: dependency selection, Joi migration, schema regression tests, Assembly Agent API migration, direct dependency cleanup, documentation that names the selected baseline.

Excluded: Messaging replacement, durable provider declarations, reactions, Runtime Bus, provider adapter migration, Assembly data migration, UI work, live provider calls, release work, and remote repository changes.

### Key Decisions

- Use consolidated Jido `release/v3` commit `ec96da6015b4b1e5a1642d50651235d9d52808ec` as the candidate. Accept it only after the gates pass.
- Public external maps and Signal data stay closed with `unrecognized_keys: :error`.
- Host-owned metadata maps remain open. Stored Jido state uses Joi stored-value validation and exact schemas.
- Replace Zoi convenience calls with equivalent Joi composition. `nullish` becomes nullable plus optional, `null` becomes `literal(nil)`, and `gte` becomes the equivalent `min` bound.
- Do not add a replacement schema package or AI package.

### Rejected Alternatives

- Keep direct Zoi use: rejected because it preserves two schema boundaries and bypasses the consolidated Jido policy.
- Add wrappers in Jido Chat for every Zoi convenience call: rejected because Joi composition is sufficient and a second facade adds no product behavior.
- Keep `jido_ai` beside consolidated Jido: rejected because the goal is one V3 runtime and the split package uses V2 helpers.
- Move Assembly to a Hex release now: rejected because this workspace must verify the reviewed exact V3 source before release work.

### Dependencies

- Consolidated Jido local repository and Git commit `ec96da6015b4b1e5a1642d50651235d9d52808ec`.
- Current Jido Chat tests, Covenant contracts, quality alias, documentation task, and coverage task.
- Jido Assembly precommit alias and current Agent tests.

### Outstanding Questions

None. The owner approved the exact-source, no-compatibility, no-extra-package, clean-seed, UI, and adapter-test recommendations on 2026-11-16.

### Sources

- [Goal brief](./2026-11-16-1135-jido-chat-assembly-v3-goal-brief.md)
- [Jido Chat manifest](../../mix.exs)
- `Jido.Joi` at consolidated Jido `release/v3:lib/jido/joi.ex`
- `jido_showcase/jido_assembly/mix.exs`

## Planning Contract

### Product Contract Preservation

Product Contract restructured without scope change: goal-brief Unit 0 maps to R1 through R7 and U1 through U4.

### Current System

Jido Chat `release/v3` pins consolidated Jido commit `047bf746330a2fbe7c3b25c045552e0303c97eaf`. Its manifest also declares Zoi `~> 0.19.0`. Direct Zoi calls exist across public values, rendering values, Signals, Actions, Runtime records, tests, and contract fixtures. Some code matches Zoi implementation structs or errors directly.

Jido Assembly declares `jido_ai ~> 2.2`, configures `:jido_ai` model aliases, defines three `Jido.AI.Agent` modules, calls generated `ask_sync`, and calls `ReqLLM` without a direct dependency. Assembly also has later dependencies on Jido Messaging and V2 Chat adapters; those remain for their later units.

### Target System

Jido Chat and Assembly use one exact consolidated Jido V3 commit. Jido Chat source constructs, parses, initializes, validates, projects, and reports schemas through `Jido.Joi`. External public maps remain closed. Host metadata remains open. Struct field projection and parse errors use supported Joi functions.

Assembly owns persona selection and message projection. Consolidated Jido owns Agent definition, graph execution, model configuration, and turn results. Assembly uses supported normal Jido runtime calls and reads credential availability without calling a transitive package.

### Key Technical Decisions

#### KTD1: Gate one exact consolidated source

- **Decision:** Use `ec96da6015b4b1e5a1642d50651235d9d52808ec` as the candidate for both packages and keep an exact Git ref during this local migration.
- **Reason:** It is the reviewed V3 head and includes the five recovery and scheduling commits after the current Chat pin.
- **Rejected alternative:** Use a moving branch ref. It cannot prove that Chat and Assembly tested the same code.
- **Consequences:** Lockfiles change. A later release unit can replace the Git ref with a released version.
- **Governs:** R1, R7; U1, U4.

#### KTD2: Use Joi as the only application schema API

- **Decision:** Replace all direct Zoi calls and types with supported `Jido.Joi` calls, compositions, accessors, and error types.
- **Reason:** Joi is the consolidated Jido V3 schema policy and supports external parsing, stored initialization, exact validation, struct projection, and JSON Schema projection.
- **Rejected alternative:** Keep direct Zoi calls only for unsupported convenience functions. This would keep a direct dependency and expose implementation details.
- **Consequences:** Private Zoi struct matches must be removed. Tests must prove semantic equivalence.
- **Governs:** R2, R3, R4; U2, U3.

#### KTD3: Keep validation boundaries explicit

- **Decision:** Keep public Signals and command/result maps closed. Keep unstructured metadata maps open. Use Joi stored-value APIs where values enter durable Agent or Runtime state.
- **Reason:** Closed public input blocks undeclared data. Open metadata lets hosts carry safe extension data. Stored values must not change during validation.
- **Rejected alternative:** Use Joi open defaults for all maps. It weakens current Signal contracts.
- **Consequences:** Each field-based map migration must state or inherit its boundary. Regression tests cover extra keys.
- **Governs:** R3; U2.

#### KTD4: Migrate Assembly to the normal consolidated turn boundary

- **Decision:** Define the personas with consolidated graph-first AI Agents and replace generated V2 helpers with supported Jido start and turn calls. Use host environment checks or a declared package boundary for credential readiness.
- **Reason:** The standalone package and generated instance API are outside the V3 target.
- **Rejected alternative:** Wrap `ask_sync` in Assembly. This hides the old contract and delays the real migration.
- **Consequences:** Agent tests and result extraction change. No live model call is required for the baseline gate.
- **Governs:** R5, R6; U4.

### System Boundaries and Change Surface

| Surface | Current contract | Planned change | Compatibility or risk |
| --- | --- | --- | --- |
| `mix.exs`, `mix.lock` | Old Jido ref plus direct Zoi | Exact V3 candidate; remove direct Zoi after migration | Dependency resolution can expose upstream changes |
| `lib/jido_chat_action*` | Direct Zoi parse, types, and exceptions | Joi parse, types, and exceptions | Public error shape must stay useful |
| `lib/jido_chat/signal/**` | Closed Zoi maps with null and range helpers | Equivalent closed Joi schemas | Extra fields, nil, and numeric bounds must not drift |
| Public value and rendering modules | Zoi structs and direct field projection | Joi structs, projection, and parse path | Defaults and portable values must stay unchanged |
| Runtime records and Agent schemas | Direct Zoi schemas | Joi stored schemas and validation | Stored data must not be coerced during validation |
| Tests and Covenant fixtures | Direct Zoi authoring and error structs | Joi authoring and supported error accessors | Test-only Zoi calls would keep the split boundary |
| Assembly dependency and config | Standalone `jido_ai` and model aliases | Consolidated Jido V3 AI configuration | Exact API must match the selected commit |
| Assembly personas and service | V2 `Jido.AI.Agent`, `ask_sync`, direct `ReqLLM` | Graph-first agents, normal turns, owned readiness check | Provider execution stays disabled in tests |

### Implementation Units

#### U1: Select and gate the consolidated source

- **Outcome:** Jido Chat resolves candidate commit `ec96da60` and passes focused compilation and tests before schema migration starts.
- **Requirements:** R1, R7.
- **Dependencies:** None.
- **Affected surfaces:** `mix.exs`, `mix.lock`, dependency code, baseline tests.
- **Implementation direction:** Inspect the five commits after the old pin. Update the exact ref and lock. Compile with warnings as errors and run the baseline, Signal, Agent, and Runtime tests. If a failure shows an upstream defect, stop and record it instead of adding a compatibility fork.
- **Test scenarios:** dependency resolves to the exact commit; application starts no Chat process; current Signals, Bus filters, Agents, and Runtime tests pass.
- **Verification:** `mix deps.get`, `mix compile --warnings-as-errors`, and focused `mix test` paths confirmed during execution.
- **Completion signal:** The lock points to `ec96da60` and focused current-behavior tests pass.

#### U2: Move all Chat schema contracts to Joi

- **Outcome:** Production and test source use Joi only, with regression evidence for public and stored-value semantics.
- **Requirements:** R2, R3.
- **Dependencies:** U1.
- **Affected surfaces:** all current files under `lib/` and `test/` that call or match Zoi; Signal schema helpers; Chat schema error formatting; portable-value and boundary tests.
- **Implementation direction:** Migrate public values first, then Signals and Actions, then Runtime and Agent schemas, then tests. Use `Jido.Joi.nullable/1 |> Jido.Joi.optional/1` for prior nullish fields, `Jido.Joi.literal(nil)` for null branches, and `Jido.Joi.min/2` for prior greater-than-or-equal bounds. Replace `Zoi.Struct` calls with Joi projection helpers. Replace direct error struct matches with Joi error accessors. Remove private schema-type inspection from rendering Signal schemas; build their wire schema from the public value schema or an explicit recursive conversion that does not name Zoi internals. Keep every field-based external map closed.
- **Test scenarios:** missing and nil optional fields; required nullable fields; lower bounds; defaults; unknown Signal fields; error paths; cards and modals with nested items; JSON round trips; stored Agent and Runtime values reject coercion.
- **Verification:** focused schema and Signal tests, plus `rg -n '\\bZoi(?:\\.|\\b)' lib test` returns no result.
- **Completion signal:** All focused tests pass and no source file names Zoi.

#### U3: Remove the split schema dependency and pass Chat gates

- **Outcome:** Jido Chat has no direct Zoi dependency and passes all package gates on the selected Jido commit.
- **Requirements:** R1, R4, R7.
- **Dependencies:** U2.
- **Affected surfaces:** `mix.exs`, `mix.lock`, docs that name Zoi as a public contract, package checks.
- **Implementation direction:** Remove the direct dependency only after U2 proof. Keep Spark and Splode. Refresh the lock without broad unrelated upgrades. Update public docs to say Joi. Run gates from fast to broad. Run the Elixir design review, fix all supported findings, and repeat affected checks.
- **Test scenarios:** dependency tree has one transitive Zoi through Jido only; package compiles; all tests and contracts pass; docs build; coverage meets the configured threshold; unused dependency check passes.
- **Verification:** commands in the Verification Contract.
- **Completion signal:** Chat gates and post-review checks pass with a clean scoped diff.

#### U4: Deferred Assembly cutover

- **Outcome:** The Assembly AI work is assigned to goal Unit 5A, where the complete V3 dependency graph can change atomically.
- **Requirements:** R5 and R6.
- **Observed dependency constraint:** A direct consolidated Jido V3 dependency requires Zoi 0.19. Current `jido_messaging` and its V2 `jido_chat` dependency require Zoi 0.18. `mix deps.get` rejects the combined graph. A dependency override would be the prohibited compatibility shim.
- **Decision:** Keep the current Assembly source buildable. Perform the AI, Chat, Messaging, adapter, and storage dependency cutover after Units 1 through 4, as goal Unit 5 already specifies.
- **Completion signal:** Goal Unit 5A passes Assembly tests and precommit on the exact V3 source with no old AI boundary.

### Work Graph

- Initial frontier: U1.
- Critical path: U1 -> U2 -> U3.
- Downstream handoff: goal Unit 5A uses the selected source after the core and adapter replacement work.
- Final integration unit: U3.

### Verification Contract

Run from `/Users/mhostetler/Source/Jido/jido_chat/jido_chat` unless a gate says Assembly.

| Gate | Applies to | Evidence | Done signal |
| --- | --- | --- | --- |
| Exact dependency | U1, U4 | `mix deps` and lock inspection | Both packages resolve `ec96da60` |
| Focused Chat behavior | U1, U2 | baseline, schema, Signal, value, Agent, Runtime tests | Named tests pass |
| No split schema API | U2, U3 | source search and dependency check | No source use and no direct dependency |
| Chat contracts | U3 | Covenant alias | Contract suite passes |
| Chat repository | U3 | compile, full tests, quality, docs, coverage, unused deps | All required gates pass |
| Assembly AI behavior | U4 | focused Agent tests without provider calls | Three personas pass |
| Assembly repository | U4 | precommit alias | Alias passes |
| Design review | U3, U4 | `kata-ex-design-review` result and fixes | No accepted finding remains |

Supported Chat commands:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix test.contracts
mix quality
mix docs
mix coveralls
mix deps.unlock --check-unused
```

Supported Assembly command from `jido_showcase/jido_assembly`:

```sh
mix precommit
```

Requirement traceability:

| Requirement | Units | Verification |
| --- | --- | --- |
| R1 | U1, U3, U4 | exact dependency and both repository gates |
| R2 | U2, U3 | source search and dependency check |
| R3 | U2 | focused semantic regression tests and full tests |
| R4 | U3 | manifest, lock, unused dependency check |
| R5 | U4 | focused persona tests and Assembly precommit |
| R6 | U4 | source and dependency inspection |
| R7 | U1-U4 | repository gates and design reviews |

### Rollout and Recovery

This is a local source migration. Keep exact Git refs and lockfile changes together. If U1 exposes an upstream defect, restore only the scoped manifest and lock edits and report the defect; do not change the shared consolidated Jido checkout. If schema tests show a semantic change, keep the direct dependency until the equivalent Joi composition is proved. Do not publish or release from this unit.

### Risks and Assumptions

- Risk: a mechanical namespace change can hide a null, default, closed-map, or stored-value change. Mitigation: semantic tests precede dependency removal.
- Risk: code that matches Zoi private structs has no direct Joi equivalent. Mitigation: replace it with explicit public wire-schema construction, not a renamed private match.
- Risk: the Assembly V2 helper can hide lifecycle work. Mitigation: test start, turn, result, and stop through the selected V3 API.
- Assumption: `ec96da60` remains available in the local Git object store or from the configured remote.
- Assumption: Assembly Agent tests can use a deterministic local fake and do not need provider credentials.

### Open Planning Decisions

None.

### Definition of Done

- U1 through U4 meet their completion signals.
- Jido Chat and Assembly resolve the same exact consolidated Jido V3 commit.
- Jido Chat source has no direct Zoi reference or dependency.
- Public Chat parsing and stored-value behavior pass the stated regression tests.
- Assembly has no standalone `jido_ai`, `config :jido_ai`, generated V2 helper, or undeclared ReqLLM call.
- All required Chat and Assembly gates pass.
- Each package has a completed Elixir design review, all accepted findings are fixed, and affected checks pass again.
- The approved goal brief remains unchanged in scope.

### Planning Sources

- [Approved goal brief](./2026-11-16-1135-jido-chat-assembly-v3-goal-brief.md)
- [Jido Chat manifest](../../mix.exs)
- Jido Chat source and tests at the Unit 0 starting commit `810ef0c265dae238d5971dc8f4ed65bab1f93892`
- Consolidated Jido `release/v3` source at `ec96da6015b4b1e5a1642d50651235d9d52808ec`
- Jido Assembly source at showcase commit `141124e`

## Adapter Results

- Markdown: canonical at `docs/plans/2026-11-16-1714-unit-0-consolidated-jido-v3-baseline-plan.md`
- HTML: not requested
- Beadwork: not requested
