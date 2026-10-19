# Adapter test kit

Use regular ExUnit tests for the stateless provider boundary. The core
[Covenant contracts](contracts.md) enforce the shared SDK boundary. See [the full SDK API](static_sdk.md) for provider callbacks and examples.

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
