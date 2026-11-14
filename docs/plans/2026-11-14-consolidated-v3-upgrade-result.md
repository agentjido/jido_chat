# Chat consolidated V3 local result

Date: 2026-11-14. Assignment: U2. Integration owner: parent Jido workspace chat.

The local Chat candidate is ready for Jidoka integration. The initial checks
below preceded commit and push authorization. No publication, core edit, database
migration, or live provider call was made. Commit and push delivery was authorized
later in this chat.

## Source and scope

- Path: `/Users/mhostetler/Source/Jido/jido_chat/jido_chat`.
- Origin: `git@github.com:agentjido/jido_chat.git`.
- Branch: `release/v3`.
- Initial HEAD: `1cae095d67c5e0e0592ec801c1714fbdcac9fa57`.
- The tree was clean before planning. The existing untracked plan was preserved.
- Initial core source and lock: exact Git revision `05723b96c6ead47dec04fe69b1c34ad62f999c54`.
- Current core source and lock: `047bf746330a2fbe7c3b25c045552e0303c97eaf`.
- Resolved registry packages: Zoi 0.19.0, ReqLLM 1.30.0, Runic 0.1.0-alpha.13,
  Nimble Options 1.2.0. Required transitive packages were added by Mix.
- No sibling dependency path or core fork is present in the Chat manifest.
- No split Action, Signal, or AI application is present in the active graph.
  Loaded Action, Signal, AI, and Agent modules all come from `jido/ebin`.

The scoped diff contains the manifest and lock, runtime identities, Agent call
results, schema policies, renamed core APIs, Plugin activation-handle adaptation,
contract fixtures, tests, and five guides. It changes 49 tracked files. At the initial return, the plan
and this result were untracked local documents. No other repository was edited.

## Interface for U5

`Jido.call/4` and `Jido.AgentServer.call/3` return
`{:ok, %Jido.AgentServer.TurnResult{}}`. Check `status: :committed` before using a
reply. A failed accepted turn is still an `:ok` transport result. Pending effects
do not prove provider completion.

For a Chat room Post, consume:

```elixir
{:ok,
 %Jido.AgentServer.TurnResult{
   status: :committed,
   reply: %Jido.Signal{
     type: "jido.chat.room.posted",
     data: %{"message" => %Jido.Signal{} = message}
   } = reply
 }} = Jido.call(jido, room_address, post_request, context: %{actor: actor})

true = Jido.Signal.get_context(reply, "jidocausationid") == post_request.id
```

The `message` is the exact fact from that Post turn. Its ID is the Post request
ID. Repeating the same Post returns the original fact without another Publish
directive or sequence increment. A conflicting Post with the same ID fails.
The new native definition module is `Jido.Chat.Runtime.Signal.Room.Posted`.
No later snapshot is used to select the result.

Room admission uses `Jido.Chat.Runtime.Room.check_member/3` or `/4`. The fourth
argument is an optional retained message Signal. The helper sends the native
`CheckMember` request with `member`, and optional `message_id` plus `message_data`.
The room checks membership and exact retained ID/data in the same turn. It
returns `MemberChecked`, type `jido.chat.room.member_checked`, with boolean data
`member` and `retained`. The helper checks the committed status, reply type,
schema, and causation ID. It returns `:ok` only for two true values. Participant
and Bridge admission use this helper.

Identity is now `Jido.Agent.Address`, with the public core `agent_address/3`
constructor. Runtime `connection_ref/1` retains its existing function name and
returns an Address. Version-1 identity maps retain `version`, `namespace`,
`partition`, and `id`. A fixed map round-trip test passes. U5 still owns its
database codec checks; no stored record was converted or rewritten here.

Room `start_agent/3` checks the full scoped Address before calling core
`start_agent/3`. Room `stop_agent/2` resolves the worker and uses core stop with
its partition. These functions do not create durable records or delete data.

## Other changes

- Normal dependency startup starts core execution support. It starts no Jido
  instance and no Chat process, room, Sensor, or storage resource.
- Room and Participant stored-state schemas use Joi constructors. Their field
  shapes stay the same. Tests instantiate both Plugins against the target.
- Renamed APIs use `Jido.Plugin.Config`, `Jido.Id`, `Jido.Signal.Codec`,
  `Jido.Trace`, and `Jido.Trace.Context`.
- Chat removes core's local self-emission hop attribute at the internal command
  execution boundary. Provider requests retain the strict Chat context policy.
- Two Signal JSON Schema fixtures now describe typed map values accurately under
  Zoi 0.19. The OpenModal Action projection permits defaulted fields to be absent,
  as the target Joi authoring contract specifies. Signal identities and provider
  payload keys did not change. Four documented Room helper arities were added to
  the public-export fixture.
- The stop test waits for core activation cleanup before it requires `:not_found`.

## Checks

Toolchain: Erlang/OTP 29, Mix/Elixir 1.20.4. The package declares Elixir `~> 1.18`;
this run does not prove every permitted toolchain version.

| Command | Exit | Result |
| --- | --- | --- |
| `mix deps.get` after targeted unlock | 0 | Exact core and registry graph resolved. |
| `mix compile --warnings-as-errors` | 0 | Final dev compilation passed. A full forced compilation also passed. |
| `MIX_ENV=test mix compile --warnings-as-errors` | 0 | Final test compilation passed. |
| `mix test test/jido_chat/runtime_room_test.exs test/jido_chat/runtime_bridge_test.exs test/jido_chat/plugin_test.exs test/jido_chat/create_thread_agent_test.exs --seed 444245` | 0 | 36 tests passed, including the earlier failing cleanup seed. |
| `mix test` | 0 | 357 tests passed before the final failed-turn outbox test was added. |
| `mix coveralls` on final state | 0 | All 358 tests passed; coverage 90.2 percent. |
| `mix test.contracts` | 0 | All 25 obligations passed. |
| `mix quality` | 0 | Format, warnings-as-errors compilation, strict Credo, Dialyzer, and Doctor passed. Dialyzer reported zero errors. |
| `mix docs -f html -f markdown` | 0 | Docs built. Generated Plugin docs warn about hidden core extension callbacks. |
| `MIX_ENV=prod mix hex.build` | 1 | Hex rejects the required Git dependency. This is a package publication limit, not a local compile failure. |
| `mix deps.tree` and module path inspection | 0 | One core provider; no active split core applications. |
| `git diff --check` | 0 | No whitespace errors. |

The first sandboxed dependency command failed because Mix could not acquire its
local TCP lock. Approved Mix execution succeeded. Initial dependency resolution
also required unlocking Nimble Options for ReqLLM 1.30. Only removed or changed
dependencies and that required constraint were unlocked. No broad dependency
update was run.

Checks used the actual exact Git source, registry dependencies, and a newly built
local dependency tree. No temporary path wiring was used. A local path candidate
is available to U5 at the repository path above. Publication needs a compatible
published consolidated core version and another package build check. Do not
change the shared core target merely to make Hex packaging pass.

## Limits and remaining ownership

No code blocker remains for local U5 integration. Jidoka itself was not compiled
or tested by U2. No live adapters, paid models, or stored databases were used.
Telegram, Discord, Slack, GitHub, Signal, Mattermost, Teams, WhatsApp, X, and
`jido_messaging` remain untested here. Their source risks are listed in the
[upgrade plan](2026-11-14-consolidated-v3-upgrade-plan.md). No broad adapter
compatibility claim is made. The public adapter operation contract was preserved.

The parent coordinator owns the combined graph, Jidoka caller changes, database
codec proof, and final application compile and behavior gates.

## Clean rebuild follow-up and cleanup

The manifest and lock now use published core commit
`047bf746330a2fbe7c3b25c045552e0303c97eaf`. The core fix puts Joi fields in a
deterministic order for checkpoint compatibility after a clean rebuild. Strict
fingerprint checks remain in place. This Chat change only updates the core pin
and lock; it changes no Chat API or stored data.

The earlier published Chat migration was
`7652b6d74c4fc8170149ae1cfd08f981cfb1ea27`. Its CI run
[43609891616](https://github.com/agentjido/jido_chat/actions/runs/43609891616)
passed compile, all four test matrix jobs, quality checks, docs, audit, and unused
dependency checks. Only Hex Package Dry Run failed: Hex does not permit the
required Git core dependency. The gate and exact Git source remain unchanged.

Cleanup inventory found only the primary Chat worktree and local `release/v3`
branch. Both are retained. No task branch or secondary worktree exists. Both plan
documents are committed. Task files under `/private/tmp/u2-*` contain source
inspection copies, an archive, temporary edit scripts, schemas, and check logs.
They can be removed after successful validation and push. No repository build
output, dependency directory, or other ignored data is included in cleanup.

Follow-up checks against the current core: `mix deps.get`, `mix quality`, and
`mix test.contracts` passed. All 358 tests passed with 90.2 percent coverage under
`mix coveralls --seed 401649 --max-cases 4`. Two earlier runs at the default
36-case concurrency each failed a different 100 ms timing check: the blocked
provider deadline test, then the Plugin mock-send message wait. The first failed
test passed in the repeat. Lower concurrency passed the full suite without a
code change or relaxed assertion. These short timing checks remain a test limit.

After the successful push, cleanup removes only the inventoried
`/private/tmp/u2-*` temporary files and core source inspection copy. This document
retains the commands, outcomes, source commits, CI evidence, and cleanup scope.

## Bridge restart test synchronization

Final-head CI run
[43613055695](https://github.com/agentjido/jido_chat/actions/runs/43613055695)
at Chat `941769ff5b6b865d660f2092d8704dbb25e2bf36` found a separate test race on
OTP 28 / Elixir 1.19, seed 917166. The pending-work recovery test called
`start_connection` immediately after `stop_connection`. Core activation cleanup
had not finished, so start returned `{:error, :recovering}`. The other three test
matrix jobs passed. Quality passed except for the known Git dependency Hex gate.

The test now waits for the public `connection_status` result `{:error, :not_found}`
before starting the replacement. It uses the existing bounded condition helper;
there is no fixed sleep increase, removed assertion, or runtime source change.
The manifest, lock, core pin, Chat API, and stored data remain unchanged by this
follow-up. The same condition is already used by the explicit connection-stop
test. The test still verifies recovery work is sent and its link is completed.

Validation passed: all 7 bridge tests with seed 917166, all 358 tests with that
seed at default concurrency, `mix quality`, and all 25 contract obligations.
The follow-up diff contains only this result document and one test synchronization
line. Task temporary CI and check logs are removed after the successful push.
