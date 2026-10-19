# Public SDK contracts

The active Covenant contracts live in `test/contracts`. They define 25 obligations
and test the current public boundary. Covenant runs only in development and test.
The SDK keeps its stateless runtime boundary.

| Component | What the tests enforce |
| --- | --- |
| Public API | Documented exports in 26 modules; all eleven main operation helpers; private options; request IDs; streams; deadlines |
| Actions | All 23 native core Actions; exact requests; validated results; safe failures; agent wire schemas; Exec, Flow, Router, Instruction, and Dispatch composition |
| Signals | All 86 identities and JSON data schemas; constructor validation; native Catalog round trips; private data rejection; files; keyboards; encoded size limits |
| Adapters | Explicit support; two adapters and clients; no I/O for unsupported calls; provider Actions and facts; configured discovery; complete ordered Delivery validation |
| Application metadata | No Chat application callback, registered process, or dependency on Jido Messaging |

Run from the package root:

```sh
mix test.contracts
mix coveralls
mix quality
```

The contract gate fails if an active obligation has no passing tagged test.
`mix test` also runs these tests. CI runs both the full suite and the contract
gate. Contract coverage and code coverage are different measurements. The package
requires code coverage above 90% and complete coverage of active obligations.

The tests compare exports and schemas with fixed JSON fixtures. They do not update
those fixtures. A breaking public change needs an explicit obligation, test, and
fixture review. Keep existing obligation IDs stable. Retire an old obligation
instead of reusing its number.

Tests use public entry points and recording adapters. Invalid input must fail
before a provider call. Success and failure results must be native Signals that
pass Catalog validation and serialization. Streaming sources stay in private
context. A deadline has an unknown provider outcome and makes no automatic retry.

The adapter contracts admit provider Actions and incoming facts through configured
discovery. Providers retain their own unit and live tests. The Telegram package
has a public API live suite and an Action live suite; neither is required for the
provider-free core contract gate.

The startup metadata contract has a narrow scope. It does not prove that every
possible implementation has no hidden state. Rendering exports are included in
the public manifest; regular unit tests check their detailed output.

See [the public API](public_api.md) for signatures, request fields, results, and
Telegram examples. See `test/contracts/README.md` in the repository for obligation
files, test files, fixture rules, and the static check command.
