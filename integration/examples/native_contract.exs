defmodule NativeContractExample.Transport do
  @behaviour Jido.Chat.Signal.Transport
  def send_message(_room, _text, _opts) do
    Process.put(:native_example_calls, Process.get(:native_example_calls, 0) + 1)
    {:ok, %{"timestamp" => 123}}
  end

  def list_groups(_opts), do: {:ok, []}
  def receive_messages(_opts), do: {:ok, []}
end

{:ok, binding} =
  Jido.Chat.bind(Jido.Chat.Signal.Adapter,
    id: "example",
    transport: NativeContractExample.Transport
  )

request =
  Jido.Chat.Signal.SendMessage.new!(%{
    "request_id" => "one",
    "room_id" => "peer",
    "text" => "hello"
  })

{:ok, result} = Jido.Chat.execute(binding, request)
{:ok, ^result} = Jido.Chat.execute(binding, request)
1 = Process.get(:native_example_calls)
true = result.type == Jido.Chat.Signal.OperationCompleted.type()
true = Jido.Signal.Context.get(result, "causationid") == request.id
true = Jido.Signal.Trace.get(result).trace_id == Jido.Signal.Trace.get(request).trace_id
catalog = Jido.Signal.Catalog.new!(Jido.Chat.signal_definitions())
{:ok, json} = Jido.Signal.Serialization.serialize(result)
{:ok, ^result} = Jido.Signal.Catalog.decode(catalog, json)
IO.puts(Jason.encode!(%{state: "pass", provider_calls: 1, native_round_trip: true}))
