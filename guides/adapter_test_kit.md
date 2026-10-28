# Adapter test kit

Use regular ExUnit tests for the stateless provider boundary. The core
[Covenant contracts](contracts.md) enforce the shared SDK boundary. See [the full SDK API](static_sdk.md) for provider callbacks and examples.

## Alignment definition

An adapter is aligned when all these statements are true:

1. **Contract alignment:** The adapter implements `channel_type/0`, `capabilities/0`,
   `invoke/3`, and `normalize/3`.
2. **Capability alignment:** Each core operation has the status `:native` or
   `:unsupported`. Each native status has an implementation.
3. **Failure alignment:** Each unsupported operation returns a typed failure with
   code `unsupported` and outcome `not_attempted`. It does not make a provider call.
4. **Result alignment:** Each native operation returns a valid canonical Jido Chat
   completion or failure Signal through the public API.
5. **Input alignment:** Provider fixtures normalize to a valid ordered `Delivery`.
   Repeated normalization of the same provider input has the same delivery and item
   identities.
6. **Source alignment:** An adapter with inbound polling or push traffic uses the
   shared `Jido.Chat.Sensor.Source` contract. A host-owned webhook can call
   `Jido.Chat.normalize/2` directly.
7. **Live alignment:** An excluded, opt-in live test uses the public Jido Chat API.
   Its environment variables are in `.env.example`. A normal test run must not make
   an external provider call.

Contract, capability, and failure alignment are automatic when a test module uses
`Jido.Chat.AdapterTestKit`. Native result and input alignment need provider fixture
tests because the test kit does not know the provider wire format. Source and live
alignment need adapter-specific tests.

```elixir
defmodule MyAdapterTest do
  use Jido.Chat.AdapterTestKit, adapter: MyAdapter

  test "one typed request returns a valid result" do
    client = Jido.Chat.Client.new!(MyAdapter,
      id: "fixture", credentials: %{token: "test"}, transport: TestTransport
    )
    request = operation_request(client, :send_message)
    result = assert_operation_success(Jido.Chat.execute(client, request))
    assert result.type == Jido.Chat.SendMessage.Completed.type()
    assert_json_round_trip(result)
  end
end
```

`operation_request/3` creates portable fixtures with an explicit client identity.
It allocates no resources. `message_received/2` creates a scoped incoming fact.
`assert_delivery/2` checks the entire ordered delivery. Unsupported operations
return `{:error, %Jido.Chat.Error{signal: failed}}`.
`assert_unsupported_operations(adapter_or_client)` executes every unsupported core
request and checks `unsupported` with outcome `not_attempted`. The default kit
includes this behavior check. Provider I/O must not occur.

The core suite checks the native adapter contract with a provider-free fixture.
Each provider package must test its adapter with a test transport.

Use `assert_operation_failure(result, catalog)` for the public Chat error return.
Success accepts both `{:ok, signal}` and `{:ok, %{signal: signal}}`. All three
Signal assertions accept an optional catalog; the default is Jido.Chat.catalog().
Use Jido.Chat.catalog(client) for core and configured provider results.
