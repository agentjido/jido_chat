# Jido Chat contracts

This directory defines the public boundary of the stateless SDK. Covenant 0.2
connects each active obligation to a named, tagged ExUnit test. CI runs the full
test suite and then the contract gate.

| Component | Definition | Tests | Active obligations |
| --- | --- | --- | ---: |
| Public API | [public_api.obligations.md](jido_chat/public_api.obligations.md) | [public_api_contract_test.exs](public_api_contract_test.exs) | 6 |
| Actions | [actions.obligations.md](jido_chat/actions.obligations.md) | [actions_contract_test.exs](actions_contract_test.exs) | 6 |
| Signals | [signals.obligations.md](jido_chat/signals.obligations.md) | [signals_contract_test.exs](signals_contract_test.exs) | 6 |
| Adapters | [adapter.obligations.md](jido_chat/adapter.obligations.md) | [adapter_contract_test.exs](adapter_contract_test.exs) | 6 |
| Application metadata | [sdk.obligations.md](jido_chat/sdk.obligations.md) | [sdk_contract_test.exs](sdk_contract_test.exs) | 1 |

The public API contract records the documented exports of 26 modules. This
includes the main functions, Client, Delivery, adapter test kit, and pure rendering
helpers. The Action contract executes all 23 core Actions. The Signal contract
records all 86 core identities and their JSON data schemas. The adapter contract
uses independent adapters and a provider extension. Tests cover valid and invalid
input, two client identities, safe failures, private options, stream consumption,
deadlines, and complete delivery validation.

## Run the gate

```sh
mix test.contracts
mix coveralls
```

Normal `mix test` also runs every contract test. Covenant is a development and
test dependency, with `runtime: false`. No contract runtime is added to the SDK.
`test/contracts/coverage.json` records obligation coverage. ExCoveralls measures
code coverage separately. Both measurements need a fresh run after a change.

For a static check without compiling or running the package:

```sh
mix covenant.check --static --contracts test/contracts --test-path 'test/contracts/**/*_test.exs'
```

## Change a contract

1. Update the applicable obligation and explain the intended public behavior.
2. Change or add its tagged test. Keep tags literal so the static check can read them.
3. Review any required export or schema fixture change.
4. Run the contract gate, unit tests, coverage, and the relevant provider tests.

Obligation IDs are stable. Retire an obligation with `status: retired`; do not
reuse its ID. Every active obligation needs a passing test. Do not skip a test or
replace its expected value with the implementation's current result to pass a change.

The fixed files in `fixtures/` are reviewed contract data. Tests never regenerate
them. `core_signals.json` contains the literal identities, schemas, and valid
examples. `public_exports.json` contains the documented function and macro arities.
`support/fixtures_helper.exs` provides recording adapters, client values, and an extension
for the tests. It uses public APIs and makes no network call.

The contract set checks observable behavior. Its startup metadata check does not
prove every possible absence of hidden runtime state. Rendering helper exports
are fixed here; their detailed rendering behavior remains in regular unit tests.
Telegram network behavior remains in the provider's excluded-by-default live suites.

The [old proposal](proposals/static_sdk_v2.md) is historical. Its proposed IDs and
code examples are not active requirements. Use the obligations listed above.
