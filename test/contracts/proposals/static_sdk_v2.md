# Proposed static SDK contracts

State: historical proposal. Date: 2026-10-17. The active core contracts are listed in
[the contract index](../README.md). This proposal includes old signatures and does
not define the current public API.

API and examples: [Static SDK API](../../../guides/static_sdk.md).

Covenant 0.2.0 accepts only active and retired obligations. It has no draft
state. This file is not named `*.obligations.md`. These proposed contracts
therefore receive no passing credit from `mix test.contracts`. Do not skip
their tests or report the proposal as enforced.

Keep the current `jido_chat.sdk.I1` active. For each implementation change,
copy the applicable requirements below to its Covenant obligation file,
add the tagged tests, show the tests fail, then implement the change.
The failed check and the implementation belong in the same change.

## Required boundaries and test cases

The IDs below are reserved for activation. All tests use public APIs and
an injected transport. They do not need Telegram credentials or network access.

| Future ID | Requirement | Required tests |
| --- | --- | --- |
| `jido_chat.sdk.I2` | Chat must own no application callback, process tree, runner, session, ETS table, persistent-term entry, process-dictionary entry, or background timer. A client is an immutable local value. Foundation applications and transient Exec tasks are allowed. | Compare Chat-owned state before and after calls, after foundation startup and completion of execution tasks. Pass the client from a short-lived creator to a second process; use it after the creator exits. In an isolated VM, start Action and Signal normally and verify Chat adds no runtime owner. |
| `jido_chat.sdk.I3` | Credentials, provider configuration, and transport must be explicit client inputs. Client construction must perform no network call, environment lookup, credential lookup, registration, or provisioning. | A recording transport sees zero calls. Conflicting application configuration does not change the client. Missing credentials fail. Two clients cannot use each other's credentials or configuration. |
| `jido_chat.sdk.I4` | Input, selected operation, client identity, and support must be validated before any provider effect. Output must be validated before success. | Invalid input, an unknown Action, a foreign-client target, and unsupported capability each produce zero transport calls. Invalid provider output produces an error with outcome `:unknown` after a write. |
| `jido_chat.sdk.I5` | Direct calls must make one operation attempt. They must not claim, cache, deduplicate, queue, or retry requests. A normal operation makes at most one write request; declared compound operations, including streams, list their writes. | Two calls with the same request ID make two transport calls. A timeout makes one call and returns outcome `:unknown`. A known rejection returns `:rejected`. A validation failure returns `:not_sent`. No automatic retry follows any of these results. |
| `jido_chat.sdk.I6` | Results must contain typed values and explicit references. They must not depend on a Chat resource store. Large results use explicit cursors or host-managed storage. | Use message and media references after the creator exits. Reject a PID, function, ETS ID, or process-local resource handle in public Signal data. A media descriptor alone does not fetch bytes. |
| `jido_chat.sdk.I7` | Normalization must be pure and bounded. It returns one complete, ordered, validated Delivery or an error. Stable event IDs include client ID, provider delivery ID, event kind, and occurrence. | Repeat the same update with the same explicit timestamps; obtain equal results. Two client IDs produce different identities. Message plus command facts retain order. A malformed candidate or exceeded byte/count bound returns no partial Delivery. No network call or store write occurs. Valid unsupported update types return an empty Delivery. |
| `jido_chat.sdk.I8` | Webhook ingestion must verify the raw request before decoding and normalization. It must not acknowledge, publish, persist, or execute a handler. | Missing, duplicate, and wrong secret headers fail before the decoder runs. A valid request returns a Delivery with no transport calls. The host selects its HTTP response after acceptance. |
| `jido_chat.sdk.I9` | Commands and facts must be native Jido Signals with explicit schema versions. Catalog validation must use an explicit definition list. Signal construction, Router matching, Dispatch, and Bus publication must not implicitly execute a Chat command. | Catalog JSON round trip retains identity and string keys. Unknown schema versions fail. Publishing a command to a Bus with no explicit command consumer causes zero provider calls. Router matching returns targets and makes zero provider calls. |
| `jido_chat.sdk.I10` | Action modules must declare input and output schemas. The facade must delegate execution to Jido Exec. Shared Actions must select the provider from execution context. Chat must own no runner or alternative execution loop. | The same SendMessage Action runs against Telegram and a second adapter using identical core input/output schemas. The facade and Exec return equivalent successful values. Capability rejection makes zero provider calls. A two-step Flow preserves dependencies and stops after a failed dependency. Effects remain deferred. Action and Signal runtime dependencies can start normally. |
| `jido_chat.sdk.I11` | Extensions must have a provider namespace, an explicit Action list, and an explicit Signal list. Extensions cannot replace a core operation or be selected from untrusted module names. | A declared Telegram Action runs through `Chat.run`. An undeclared Action, another provider's Action, a duplicate schema pair, and a core override fail before transport. Core callers can ignore Telegram extension Signals. |
| `jido_chat.sdk.I12` | Streaming is a caller-owned operation. It consumes chunks incrementally, applies explicit limits, and stops before the next write after cancellation. Any fallback must be declared and explicitly allowed. | Use a lazy producer to prove a first write occurs before the producer ends. Cancel and prove there are no later writes or chunk reads. Reject an unsupported stream before consumption. A timed-out write returns `:unknown`; there is no replay. No `Enum.to_list` of the full stream. |
| `jido_chat.sdk.I13` | Capabilities must describe actual provider behavior. Fallbacks must be named and opt-in. The SDK must not fabricate history, message storage, subscriptions, or unsupported features. | Telegram history reports `:unsupported` where the provider has no matching read API. An unsupported call makes zero requests. A fallback is rejected by default, and its approved path is tested separately. Every native operation has a transport contract test. |
| `jido_chat.sdk.I14` | Client inspection, Signals, receipts, errors, and SDK telemetry must exclude secrets and raw private requests. Error codes and outcome classes must be stable. | Insert a unique test secret in credentials and a failing response. Search all public outputs and captured SDK telemetry for it. Verify credential-safe client inspection and redacted transport errors, including token-bearing URLs. |
| `jido_chat.sdk.I15` | Router composition must use trusted target configuration and explicit input projection. Catalog validation precedes routing of external commands. A command requires exactly one approved target. Facts can use explicitly selected fan-out. | Unknown schema versions fail before projection or execution. Zero or multiple command targets make zero provider calls. An exact command route plus an overlapping wildcard is ambiguous, not two writes. A fact can route to both an observer and a handler when fan-out is selected. Routing alone has no side effect. |

The supported runtime dependency is `jido_action` with `runtime: true`.
I2 restricts Chat-owned state. It does not prohibit foundation applications or
the tasks that native Exec uses. I10 requires the facade to use Exec rather
than maintain another validation and execution loop.

For I10 and I14, run a provider failure through the Action, a nested Flow, the
facade, and public error serialization. Verify that sanitized provider code and
outcome survive each path. Exec's own validation errors keep their own taxonomy.
All facade calls use one attempt. A direct Exec caller selects its own policy;
neither an unknown write nor a timeout is marked retryable by Chat.

For I8, run the proposed ReceiveWebhook Flow with an invalid secret and verify
that its normalization step never runs. For I15, test both Instruction templates
and bound native Instructions; a route cannot introduce private credentials into
portable parameters or metadata.

The per-call process-state checks are regression checks. Add a source audit and
an isolated VM test for package startup. A metadata test alone cannot prove
that the whole package is free of hidden state.

## Proposed public tests

These are test specifications for the future API. `ContractTransport` is a
future test fixture. It returns scripted responses and sends each call to the
test process. It owns no production state. Its messages include the caller PID.
The Telegram adapter conformance suite uses the same core contract cases.

```elixir
defmodule Jido.Chat.StaticSDKContractTest do
  use Covenant.Case, component: "jido_chat.sdk", async: true

  alias Jido.Chat
  alias Jido.Chat.SendMessage
  alias Jido.Chat.Test.ContractTransport

  @tag obligation: "jido_chat.sdk.I3"
  test "client creation does not call the provider" do
    assert {:ok, _client} = Chat.client(ContractAdapter,
      id: "bot-a",
      credentials: %{token: "test-secret"},
      transport: {ContractTransport, owner: self(), response: :message}
    )

    refute_received {:provider_call, _, _, _}
  end

  @tag obligation: "jido_chat.sdk.I4"
  test "invalid input fails before transport" do
    client = contract_client(self(), :message)
    assert {:error, %{code: :invalid_input, outcome: :not_sent}} =
      Chat.run(client, SendMessage, %{room_id: "42"})
    refute_received {:provider_call, _, _, _}
  end

  @tag obligation: "jido_chat.sdk.I5"
  test "a request ID does not install deduplication" do
    client = contract_client(self(), :message)
    params = %{room_id: "42", text: "Hello"}

    assert {:ok, _} = Chat.send_message(client, params, request_id: "r1")
    assert {:ok, _} = Chat.send_message(client, params, request_id: "r1")
    assert_received {:provider_call, _, :send_message, ^params}
    assert_received {:provider_call, _, :send_message, ^params}
    refute_received {:provider_call, _, _, _}
  end

  @tag obligation: "jido_chat.sdk.I5"
  test "a write timeout has an unknown outcome and is not retried" do
    client = contract_client(self(), :timeout)

    assert {:error, %{code: :timeout, outcome: :unknown}} =
      Chat.send_message(client, %{room_id: "42", text: "Hello"})

    assert_received {:provider_call, _, :send_message, _}
    refute_received {:provider_call, _, _, _}
  end

  @tag obligation: "jido_chat.sdk.I2"
  test "a client does not depend on its creator process" do
    owner = self()
    {pid, monitor} = spawn_monitor(fn ->
      send(owner, {:client, contract_client(owner, :message)})
    end)

    assert_receive {:client, client}
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}
    assert {:ok, _} = Chat.send_message(client, %{room_id: "42", text: "Hello"})
    assert_received {:provider_call, _, :send_message, _}
  end
end
```

## Provider conformance cases

The proposed `Jido.Chat.AdapterContract` helper supplies assertions for
configuration, capabilities, supported operations, normalization, credential
isolation, and error conversion. Each provider writes literal tagged tests
and supplies its fixtures and transport expectations. Passing the core suite
does not prove provider support; each provider must pass its own cases in CI.

```elixir
# Future jido_chat_telegram/test/contracts/adapter_contract_test.exs
defmodule Jido.Chat.Telegram.AdapterContractTest do
  use Covenant.Case, component: "jido_chat_telegram.adapter", async: true

  @tag obligation: "jido_chat_telegram.adapter.I1"
  test "send_message uses the core input and output contract" do
    Jido.Chat.AdapterContract.assert_operation(
      Jido.Chat.Telegram.Adapter,
      Jido.Chat.Telegram.ContractFixtures.send_message()
    )
  end
end
```

Each provider must keep its own active Covenant files. Keep tags and tests
literal so Covenant's static check can read them without macro expansion.
The future assertion helper needs its own tests; it does not exist today.

## Messaging contracts

Activate these in `jido_messaging`, with its own test fixtures and Covenant gate.

| Future ID | Requirement | Required tests |
| --- | --- | --- |
| `jido_messaging.chat.I1` | Messaging owns supervision, provider polling, offsets, leases, session state, subscriptions, queues, rate limits, and durable execution. | Restart each worker and prove state recovery through the configured persistence backend. No Chat private module is used. |
| `jido_messaging.chat.I2` | Acceptance validates and deduplicates a whole Delivery, persists authoritative records and an outbox, then publishes facts. | Reject an invalid candidate with no partial commit. Duplicate provider deliveries create one logical record. Crash between commit and publication; recover the outbox. |
| `jido_messaging.chat.I3` | Provider execution requires an authorized command, a request claim, and an explicit retry policy. Unknown writes must not be repeated automatically. | Reject unauthorized work before provider access. Race two workers for one claim. Simulate a crash after the provider write. Recover as uncertain until reconciliation or explicit operator action. |
| `jido_messaging.chat.I4` | Bus durability depends on its configured store. Bus delivery does not replace application acceptance, an outbox, or provider idempotency. | Memory-store restart loses records as documented. A durable store retains them. A redelivered Bus record does not repeat an already accepted provider write. |

## Change order

1. Client, explicit transport, and direct send/read/error tests: I2–I6, I13–I14.
2. Pure normalization, verified ingestion, and portable Signal tests: I7–I9.
3. Adapter-agnostic Action, Flow, and Router tests: I10 and I15. Foundation applications can start as normal dependencies.
4. Telegram extension and conformance tests: I11. Then bounded streams: I12.
5. Messaging acceptance, outbox, retry, and recovery contracts in its package.
6. Migrate callers, remove the old stateful API, and release a breaking version.
