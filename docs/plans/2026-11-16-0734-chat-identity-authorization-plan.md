---
title: Pluggable Chat identity and authorization
type: implementation-plan
date: 2026-11-16
last_reviewed: 2026-11-16
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Pluggable Chat identity and authorization

## Goal Capsule

- Objective: Let a host connect its existing identity and authorization systems to Jido Chat without another package.
- Means: Add small public identity and authorization behaviours, enforce them at Jido Plugin admission, and keep existing callers compatible when the new integration is not configured.
- Authority: Local product code, tests, and guides in this repository. No commit, push, dependency, release, or sibling repository change.
- Stop conditions: Stop if the work needs a new dependency, credential storage, a global identity data model, or a change to Jido Core.
- Next executor: Jido Chat implementer and verifier.

## Product Contract

### Summary

Jido Chat supplies a small identity reference and two host extension points. The host resolves an external actor to a Chat principal and decides whether that principal can perform a Chat action on a resource.

### Problem Frame

The current Room Plugin compares `caller_context.actor` directly with the configured administrator and member list. The Agent Plugin scopes provider input by connection and room but does not resolve the external actor to a host principal. A host must be able to connect its existing identity system without copying credentials or user records into Chat.

### Actors

- A host application that owns authentication and identity records.
- A provider adapter that supplies a provider-scoped external actor ID.
- A Jido Agent or Room that consumes an admitted Chat principal.

### Requirements

- **R1:** Jido Chat defines a validated, credential-free principal value.
- **R2:** Jido Chat defines a provider-scoped identity source and an identity provider behaviour.
- **R3:** A host can configure identity through the Chat Agent DSL or application configuration.
- **R4:** Jido Chat defines an authorizer behaviour that checks principal, action, resource, and context.
- **R5:** Room admission uses resolved identity and the configured authorizer instead of direct actor comparisons.
- **R6:** Agent Plugin ingress resolves and authorizes external actors before the Agent turn and exposes the principal in trusted action context.
- **R7:** Configured identity and authorization fail closed. Existing unconfigured integrations keep their current behavior.
- **R8:** Signals, messages, and stored Room state do not gain credentials, tokens, proofs, or full external profiles.

### Key Flows

Provider input flows through connection scope validation, identity resolution, resource authorization, Jido admission, and then the selected Agent action. Local Room calls flow through caller identity resolution, Room authorization, and the existing Room state transition.

### Acceptance Examples

- A configured host identity provider maps one provider actor to a canonical Chat principal.
- Two equal external IDs in different provider accounts produce different identity sources.
- An unknown actor, invalid provider response, provider exception, or authorization denial prevents the turn.
- Direct AgentServer input cannot bypass configured provider identity admission.
- Existing Room and Agent Plugin tests pass when identity integration is not configured.
- No identity value contains a credential, token, or proof field.

### Success Criteria

Focused identity, authorization, Room, and Agent Plugin tests pass. The full test suite, contract suite, and repository quality gate pass or have one explicit environment limit.

### Scope Boundaries

In scope: public value types, behaviours, built-in local providers and authorizers, Room admission, Agent Plugin ingress, configuration, tests, and guides.

Out of scope: another package, login, OAuth, credential verification, account linking, global grants, organization policy storage, Jidoka tool policy, UI, and changes to provider adapter repositories.

### Key Decisions

- The host remains the identity system of record.
- Chat stores principal IDs only where Chat state already needs an actor or member.
- Provider identity keys include provider, account, and external ID.
- Application configuration is a fallback. Agent or Room configuration is more specific.

### Rejected Alternatives

- Copy the complete `jido_messaging` principal, credential, and grant system. This adds global identity ownership to Chat.
- Add a `jido_identity` package. The user explicitly excluded another package.
- Put identity claims in Signal extensions. The Signal policy permits only trace and causation fields.

### Dependencies

The current Jido dependency already supplies Plugin `admit/3`. No dependency change is required.

### Outstanding Questions

None blocking. A later release can add durable Room roles without changing these behaviours.

### Sources

- `lib/jido_chat/runtime/room/plugin.ex`
- `lib/jido_chat/plugin.ex`
- `lib/jido_chat/plugin/runtime.ex`
- `lib/jido_chat/signal/policy.ex`
- `deps/jido/lib/jido/plugin.ex`
- `deps/jido/lib/jido/plugin/context/admission.ex`

## Planning Contract

### Product Contract Preservation

Product Contract unchanged.

### Current System

The Room Plugin receives live caller context in `admit/3` and performs four direct actor comparisons. The Agent Plugin validates a fixed Client source, configured room, and declared event before it calls AgentServer. The Plugin runtime records short interaction-to-room grants. Signals reject private data and permit only trace context fields.

### Target System

```text
trusted adapter or host call
  -> provider-scoped IdentitySource
  -> host IdentityProvider
  -> validated Principal
  -> host or built-in Authorizer at the exact Chat resource
  -> Jido Plugin admission
  -> Agent or Room action
```

Principal data remains transient during admission unless an existing Chat record needs the principal ID. Provider credentials remain in the Client or host.

### Key Technical Decisions

#### KTD1: Use public behaviours and validated values

- Decision: Add `Jido.Chat.IdentityProvider` and `Jido.Chat.Authorizer`, with Zoi-backed `Principal` and `IdentitySource` values.
- Reason: R1, R2, and R4 need a small stable host contract.
- Rejected alternative: A callback function as the only public contract. Modules are easier to validate, document, configure, and test.
- Consequences: Hosts implement two small modules. Built-in test providers can use functions and static maps.
- Governs: R1, R2, R4, U1.

#### KTD2: Use Jido Plugin admission as the enforcement point

- Decision: Resolve and authorize before execution, then bind Agent ingress to the Plugin runtime admission record.
- Reason: The active Jido V3 API gives `admit/3` live caller context and can reject a turn without changing the Signal.
- Rejected alternative: Add identity to Signal data or extensions. This makes a sender-controlled value look trusted and conflicts with Signal policy.
- Consequences: Direct unregistered provider facts fail when access integration is configured.
- Governs: R5, R6, R7, U2, U3.

#### KTD3: Preserve compatibility through an explicit unconfigured mode

- Decision: Existing Agent Plugin behavior remains active when no identity provider is configured. Rooms use a built-in trusted-caller provider and the existing membership policy through the new behaviours.
- Reason: This is an additive V3 interface. Existing integrations must not fail only because the extension points now exist.
- Rejected alternative: Make `DenyAll` the global default for all current Agents. That is secure but is a breaking policy change.
- Consequences: Production hosts enable strict identity per Agent or through application configuration. Room authorization stays fail closed for its current rules.
- Governs: R3, R5, R7, U2, U3.

### System Boundaries and Change Surface

| Surface | Current contract | Planned change | Compatibility or risk |
| --- | --- | --- | --- |
| Core identity values | Message `Actor` only | Add `Principal` and provider-scoped `IdentitySource` | Additive public API |
| Host integration | No identity or authorization behaviour | Add two validated behaviours and safe invocation wrappers | Provider failures deny |
| Room Plugin | Direct actor comparisons | Resolve principal and call Room authorizer | Preserve member state shape |
| Agent Plugin DSL | Connections only | Add optional identity and authorizer settings | Existing DSL remains valid |
| Agent Plugin runtime | Interaction grants only | Add short, one-use admission records for configured identity | Bounded transient memory |
| Action context | Connection, Client, adapter | Add trusted principal when configured | Additive map key |
| Guides and tests | No host identity example | Add configuration and security examples | No adapter change |

### Implementation Units

#### U1: Public identity and authorization contracts

- Outcome: Validated values, behaviours, invocation wrappers, and built-in providers and authorizers exist.
- Requirements: R1, R2, R4, R7, R8.
- Dependencies: None.
- Affected surfaces: New `lib/jido_chat` modules and focused tests.
- Implementation direction: Keep all values credential-free. Validate callback modules and callback results. Convert exceptions and invalid results to closed errors. Include static, function, trusted-caller, trusted-agent, deny-all, Room-policy, and Room-role helpers where they have direct tests.
- Test scenarios: Valid values, invalid values, account-scoped sources, callback errors, invalid callback returns, static lookup, function lookup, agent identity, deny, and Room permission rules.
- Verification: Run focused identity and authorization tests.
- Completion signal: Public contracts compile, document, and fail closed under negative tests.

#### U2: Room admission integration

- Outcome: Room admission resolves a principal and delegates every Room permission check to an authorizer.
- Requirements: R3, R5, R7, R8.
- Dependencies: U1.
- Affected surfaces: Room Plugin, Room tests, Runtime guide.
- Implementation direction: Add Room DSL options with compatible defaults. Build identity source from explicit host context or the current trusted actor. Pass only transient principal and decision data to action context. Do not change stored member or message schemas.
- Test scenarios: Existing Room flows, external provider mapping, provider denial, authorizer denial, and actor spoof mismatch.
- Verification: Run `runtime_room_test.exs` and focused access tests.
- Completion signal: Existing Room behavior passes and configured external identity controls admission.

#### U3: Agent Plugin ingress integration

- Outcome: Configured provider facts resolve and authorize one external actor before Agent execution, and the Agent receives the trusted principal.
- Requirements: R3, R6, R7, R8.
- Dependencies: U1.
- Affected surfaces: Agent Plugin DSL, Plugin runtime, Plugin tests, Agent Plugin guide.
- Implementation direction: Resolve configuration at activation. Build identity source only from the fixed Client, adapter channel, and normalized actor field. Register a bounded one-use admission record before AgentServer call. The Plugin `admit/3` consumes and verifies that record for inbound provider facts. Internal command Signals remain unaffected.
- Test scenarios: Configured success, unknown actor, denial, invalid callback, direct-call bypass, equal external IDs under different Clients, and unconfigured regression.
- Verification: Run Plugin tests and focused identity ingress tests.
- Completion signal: A configured principal is available at `context.chat.principal`, and no unregistered provider fact executes.

#### U4: Public contract and repository integration

- Outcome: Guides describe host integration and all repository gates pass.
- Requirements: R1-R8.
- Dependencies: U2, U3.
- Affected surfaces: Public API contract fixtures if required, guides, full test and quality gates.
- Implementation direction: Add only documented public exports that the repository contract requires. Explain trust boundaries and show one host module example without credentials.
- Test scenarios: Contract suite, full suite, format, compile, Credo, Dialyzer, and Doctor.
- Verification: Run supported repository commands.
- Completion signal: No contract drift or relevant regression remains.

### Work Graph

- Initial frontier: U1.
- Parallel after U1: U2 and U3.
- Critical path: U1 -> U3 -> U4.
- Final integration unit: U4.

### Verification Contract

| Gate | Applies to | Evidence | Done signal |
| --- | --- | --- | --- |
| Focused contracts | U1 | New identity and authorization tests | Positive and negative cases pass |
| Room behavior | U2 | `mix test test/jido_chat/runtime_room_test.exs` plus focused tests | Existing and configured flows pass |
| Agent ingress | U3 | `mix test test/jido_chat/plugin_test.exs` plus focused tests | Principal binding and bypass denial pass |
| Public contracts | U4 | `mix test.contracts` | All obligations pass |
| Repository regression | U4 | `mix test` | Full suite passes |
| Static quality | U4 | `mix quality` | All configured checks pass |

Run commands from `/Users/mhostetler/Source/Jido/jido_chat/jido_chat`.

### Rollout and Recovery

The change is additive. Unconfigured Agent Plugins keep current behavior. Enable identity and authorization on one Agent first. A host can recover by removing those optional settings. Room defaults preserve the current trusted-caller and membership rules. No stored-data migration or rollback is required.

### Risks and Assumptions

- Risk: A host treats provider display data as identity. Prevention: `IdentitySource` uses only fixed provider, account, and external IDs.
- Risk: A direct AgentServer call bypasses configured ingress. Prevention: one-use Plugin runtime admission records.
- Risk: Callback failures disclose details or permit work. Prevention: closed errors and no credentials in callback values.
- Risk: Admission records grow without limit. Prevention: short expiry and a fixed maximum pending count.
- Assumption: The host or adapter has already authenticated its transport. Chat resolves identity; it does not verify transport credentials.

### Open Planning Decisions

None.

### Definition of Done

- R1-R8 have implementation and direct evidence.
- No dependency or sibling repository changes exist.
- Existing unconfigured behavior passes regression tests.
- Configured identity and authorization deny unknown, invalid, expired, or bypass input.
- Public guides show the host integration and trust boundary.
- Focused tests, full tests, contracts, and quality pass or report one exact environment limit.

### Planning Sources

- Repository files listed under Product Contract Sources.
- `AGENTS.md`, `README.md`, `mix.exs`, `guides/agent_plugin.md`, and `guides/runtime.md`.

## Adapter Results

- Markdown: canonical at `docs/plans/2026-11-16-0734-chat-identity-authorization-plan.md`
- HTML: not requested
- Beadwork: not requested
