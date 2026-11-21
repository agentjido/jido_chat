# Telegram contracts

The active Covenant contracts are in `test/contracts`. They define 18 obligations
with 25 tests. Covenant runs only in development and test. The provider keeps its
stateless SDK boundary.

| Component | What the tests enforce |
| --- | --- |
| Adapter | Public exports; exact capabilities; all 12 supported core operations; ten incoming event types; ordered normalization; portable files; explicit offsets; draft and edit stream delivery |
| Actions | All 14 extensions through Exec and Chat; two clients; exact provider calls; validated results; safe failures; private webhooks; mixed Flow and Router composition; agent wire schemas |
| Signals | All 42 identities and JSON data schemas; required fields; Catalog round trips; trace context; privacy at execution; Telegram field limits; encoded Signal and Delivery limits |

Run from the package root:

```sh
mix test.contracts
mix coveralls
mix quality
```

Normal `mix test` runs the contracts. CI runs the full suite and the contract
gate. Code coverage has a 90% minimum. Contract coverage requires a passing test
for every active obligation.

The tests use fixed fixtures, fake credentials, and a recording transport.
Fixtures are reviewed data; tests never update them. A public breaking change
needs an explicit obligation, test, and fixture review. The
[shared SDK contracts](../contracts.md) cover the common behavior. These contracts
cover Telegram mappings and behavior.

The host owns polling loops, acknowledgements, offset storage, listeners, HTTP
responses, and retries. FetchUpdates makes one explicit read and returns the next
offset. Streaming work ends with the call. Private credentials and transport
options remain outside Signals. The shared Chat execution boundary validates
accepted provider requests and typed results.

The contract suite makes no provider call. Regular unit tests check HTTP transport
details. The live suites check the real provider and remain excluded by default.
See the [Telegram guide](telegram.md) for live commands and the `test/contracts/README.md` repository
file for obligation definitions, fixture rules, and the static check command.
