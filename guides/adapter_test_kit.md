# Adapter Test Kit

`Jido.Chat.AdapterTestKit` is provider-free ExUnit support for independent
adapter packages. It is in the `jido_chat` Hex package under `lib/`. An adapter
package does not need its provider SDK to compile or run the kit itself.

Add `jido_chat` to the test environment if it is not already a runtime
dependency:

```elixir
def deps do
  [
    {:jido_chat, "~> 1.1", only: :test}
  ]
end
```

## Minimal adapter

The canonical adapter has three required callbacks. Declare each capability
explicitly. A `:native` declaration must have its matching callback.

```elixir
defmodule MyAdapter do
  use Jido.Chat.Adapter

  @impl true
  def channel_type, do: :my_provider

  @impl true
  def transform_incoming(payload) do
    {:ok,
     %{
       external_room_id: payload["room_id"],
       external_user_id: payload["user_id"],
       external_message_id: payload["message_id"],
       text: payload["text"],
       raw: payload
     }}
  end

  @impl true
  def send_message(room_id, text, _opts) do
    {:ok,
     %{
       external_room_id: room_id,
       external_message_id: "provider-message-1",
       metadata: %{text: text}
     }}
  end

  @impl true
  def capabilities do
    %{
      send_message: :native,
      edit_message: :unsupported,
      delete_message: :unsupported
    }
  end
end
```

Add one baseline conformance module. The generated tests check capability
coherence and stable results for unsupported operations.

```elixir
defmodule MyAdapter.ConformanceTest do
  use Jido.Chat.AdapterTestKit, adapter: MyAdapter, async: true
end
```

## Provider extensions

Use `capability_test/3` for tests that need provider fixtures or a provider
client mock. The body runs only when the capability is `:native` or
`:fallback`.

```elixir
defmodule MyAdapter.ProviderContractTest do
  use Jido.Chat.AdapterTestKit, adapter: MyAdapter, async: true

  capability_test :edit_message, "normalizes an edit response" do
    result =
      Jido.Chat.Adapter.edit_message(
        @adapter,
        "room-1",
        "provider-message-1",
        "New text"
      )

    assert_capability_result(@adapter, :edit_message, result)
  end

  test "turns a provider webhook into an EventEnvelope" do
    request =
      webhook_request(
        adapter_name: :my_provider,
        payload: %{
          "room_id" => "room-1",
          "user_id" => "user-1",
          "message_id" => "provider-message-1",
          "text" => "Hello"
        }
      )

    assert %Jido.Chat.EventEnvelope{} = assert_webhook_event(@adapter, request)
  end
end
```

`assert_capability_result/3` has contract checks for posting, editing,
deletion, reactions, thread operations, file operations, media fetches, and
message pages. Other shared assertions check normalized responses, message
identifiers, canonical media, JSON serialization, and webhook event envelopes.

## Factories and deterministic mocks

`Jido.Chat.AdapterTestKit.Factories` supplies fixed authors, messages, media,
incoming events, event envelopes, webhook requests, post payloads, and adapter
responses. Each function accepts a map or keyword list of field overrides.

`Jido.Chat.AdapterTestKit.MockState` gives each test a resettable state process.
`Jido.Chat.AdapterTestKit.MockTransport` records ordered calls and consumes a
response queue. `Jido.Chat.AdapterTestKit.MockAdapter` implements the common
native operation shapes and can use the mock transport:

```elixir
transport = start_supervised!(Jido.Chat.AdapterTestKit.MockTransport)

{:ok, response} =
  Jido.Chat.Adapter.send_message(
    Jido.Chat.AdapterTestKit.MockAdapter,
    "room-1",
    "Hello",
    transport: transport
  )

assert response.external_message_id == "mock-message-1"
assert [%{operation: :send_message}] =
         Jido.Chat.AdapterTestKit.MockTransport.calls(transport)
```

The kit does not replace provider integration tests. Keep credential checks,
provider emulators, and provider SDK behavior in the adapter package.
