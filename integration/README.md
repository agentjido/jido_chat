# Public Signal integration checks

The default `all` profile loads core, Messaging, and all nine provider adapters.
Use this profile for G7 and final whole-group verification.

The `runtime` profile loads core, Messaging, and the Signal provider. Use it for
G3 runtime checks. It proves runtime behavior before the other adapter ports are
complete. G7 still requires all nine adapters.

Use separate build paths to test with and without the optional AI dependency.
From this directory, run the runtime checks with AI excluded:

```sh
export MIX_ENV=test JIDO_CHAT_PATH=.. JIDO_INTEGRATION_PROFILE=runtime
export JIDO_INTEGRATION_AI=0 MIX_BUILD_PATH=_build/runtime-core
mix deps.get
mix compile --warnings-as-errors
mix test ../test --seed 0 --warnings-as-errors
mix test ../../jido_messaging/test --include integration --include story --exclude flaky --seed 0 --warnings-as-errors
mix test test --seed 0 --warnings-as-errors
mix run scripts/report_dependency_graph.exs
```

Set `JIDO_MESSAGING_POSTGRES_URL` to the local fixture database to include the
PostgreSQL tests. The harness excludes live tests. It excludes PostgreSQL tests
only when this fixture is absent.

Run the complete suites in separate BEAM processes. Core and Messaging contain
a test module with the same name. Separate processes preserve every test and
prevent module replacement.

Then run the same commands with `JIDO_INTEGRATION_AI=1` and
`MIX_BUILD_PATH=_build/runtime-ai`. Also run the declared optional AI fixture:

```sh
mix run ../../jido_messaging/test/optional/jido_ai_integration.exs
```

The graph report checks the exact pinned Git commits and package versions.
It records source hashes for the path dependencies. Set
`JIDO_INTEGRATION_GRAPH_OUTPUT` to save the report at a selected evidence path.

For final checks, set `JIDO_INTEGRATION_PROFILE=all` and use separate whole-group
build paths. The API audit also requires the full group when `--phase G7` is used:

```sh
mix run scripts/audit_api_exports.exs --phase G7
mix run scripts/verify_signal_migration.exs --phase all --manifest ../docs/migration/version-matrix.json
```
