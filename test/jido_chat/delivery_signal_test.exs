defmodule Jido.Chat.DeliverySignalTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{Delivery, Signal}
  alias Jido.Chat.Errors.Contract

  defmodule Adapter do
    def channel_type, do: :test
    def capabilities, do: %{}
    def invoke(_, _, _), do: {:error, :unsupported}
    def normalize(_binding, %Delivery{} = delivery, _opts), do: {:ok, delivery}
    def normalize(_binding, _raw, _opts), do: {:ok, %{"raw" => "forbidden"}}
  end

  setup do
    assert {:ok, binding} = Jido.Chat.Client.new(Adapter, id: "binding-1")
    %{binding: binding}
  end

  test "zero, one, and many facts keep the complete validated order", %{binding: binding} do
    facts = Enum.map(1..3, &message(binding, &1))

    for items <- [[], Enum.take(facts, 1), facts] do
      assert {:ok, delivery} = Delivery.new(binding, "delivery-1", items)
      assert delivery.signals == items
      assert {:ok, ^delivery} = Jido.Chat.normalize(binding, delivery)
    end

    assert {:error, %Contract{code: :invalid_delivery}} = Jido.Chat.normalize(binding, %{"raw" => true})
  end

  test "every item is checked before authoritative processing", %{binding: binding} do
    valid = message(binding, 1)
    invalid = %{valid | data: %{"raw" => "private"}}
    assert {:error, %Contract{}} = Delivery.new(binding, "delivery-1", [valid, invalid])

    assert {:error, %Contract{code: :context_mismatch}} =
             Delivery.new(binding, "delivery-1", [%{valid | source: "/other"}])

    assert {:error, %Contract{code: :context_mismatch}} = Delivery.new(binding, "wrong-delivery", [valid])

    assert {:ok, request} =
             Signal.SendMessage.new(%{
               "client_id" => binding.id,
               "request_id" => "request-1",
               "room_id" => "room-1",
               "text" => "hello"
             })

    assert {:error, %Contract{code: :context_mismatch}} = Delivery.new(binding, "delivery-1", [request])
  end

  test "invalid delivery shapes and empty delivery limits fail before fact processing", %{binding: binding} do
    for {id, signals} <- [{"", []}, {<<255>>, []}, {nil, []}, {"valid", nil}, {"valid", :invalid}] do
      assert {:error, %Contract{code: :invalid_delivery}} = Delivery.new(binding, id, signals)
    end

    assert {:error, %Contract{code: :invalid_delivery}} = Delivery.validate(nil, %{})
    assert {:ok, empty} = Delivery.new(binding, "empty", [])
    assert Delivery.validate_empty(empty) == {:ok, empty}
    assert {:error, %Contract{code: :invalid_delivery}} = Delivery.validate_empty(%{empty | id: ""})

    assert {:error, %Contract{code: :invalid_delivery}} =
             Delivery.validate_empty(%{empty | signals: [message(binding, 1)]})

    assert {:error, %Contract{code: :invalid_delivery}} = Delivery.validate_empty(%{})

    assert {:error, %Contract{code: :delivery_too_large}} =
             Delivery.validate_empty(%{empty | id: String.duplicate("x", 1_048_576)})
  end

  test "100 items and 20 failure facts are allowed; one extra rejects the delivery", %{binding: binding} do
    messages = Enum.map(1..100, &message(binding, &1))
    assert {:ok, _} = Delivery.new(binding, "delivery-1", messages)

    assert {:error, %Contract{code: :too_many_signals}} =
             Delivery.new(binding, "delivery-1", messages ++ [message(binding, 101)])

    failures =
      Enum.map(1..21, fn index ->
        Signal.NormalizationFailed.new!(
          %{
            "item_id" => "failed-#{index}",
            "delivery_id" => "delivery-1",
            "code" => "invalid_item",
            "item_index" => index
          },
          source: binding.source
        )
      end)

    assert {:ok, delivery} = Delivery.new(binding, "delivery-1", Enum.take(failures, 20))
    assert delivery.signals == Enum.take(failures, 20)
    assert {:error, %Contract{code: :too_many_failures}} = Delivery.new(binding, "delivery-1", failures)
  end

  test "encoded delivery size is accepted at 1 MiB and rejected one byte beyond", %{binding: binding} do
    first = Enum.map(1..4, &message(binding, &1, String.duplicate("x", 260_000)))
    last = message(binding, 5)
    base_size = delivery_size(first ++ [last])
    fill = 1_048_576 - base_size
    assert fill > 0
    last = message(binding, 5, String.duplicate("x", fill))
    assert delivery_size(first ++ [last]) == 1_048_576
    assert {:ok, _} = Delivery.new(binding, "delivery-1", first ++ [last])
    beyond = message(binding, 5, String.duplicate("x", fill + 1))
    assert {:error, %Contract{code: :delivery_too_large}} = Delivery.new(binding, "delivery-1", first ++ [beyond])
  end

  defp message(binding, index, text \\ "") do
    Signal.MessageReceived.new!(
      %{
        "item_id" => "item-#{index}",
        "delivery_id" => "delivery-1",
        "room_id" => "room-1",
        "message_id" => "message-#{index}",
        "sender" => %{"id" => "actor-1"},
        "text" => text
      },
      id: "fixture-#{index}",
      time: "2026-10-12T12:00:00Z",
      source: binding.source,
      subject: Signal.Identity.conversation_subject(binding.id, "room-1")
    )
  end

  defp delivery_size(signals),
    do: Jason.encode!(%{"id" => "delivery-1", "signals" => Enum.map(signals, &Jido.Signal.to_map/1)}) |> byte_size()
end
