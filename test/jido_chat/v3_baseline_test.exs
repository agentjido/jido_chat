defmodule Jido.Chat.V3BaselineTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.{Bus, Catalog, Serialization}

  defmodule MessageReceived do
    use Jido.Signal,
      type: "jido.chat.baseline.message_received",
      default_source: "urn:jido:chat:binding:fixture",
      dataschema: "urn:jido:chat:schema:baseline:1",
      schema: Zoi.object(%{"text" => Zoi.string()}, unrecognized_keys: :error)
  end

  test "catalog JSON decoding preserves the complete typed fact" do
    catalog = Catalog.new!([MessageReceived])

    assert {:ok, signal} =
             MessageReceived.new(%{"text" => "hello"}, subject: "room:fixture")

    assert {:ok, encoded} = Serialization.serialize(signal)
    assert {:ok, ^signal} = Catalog.decode(catalog, encoded)
    assert {:ok, ^signal} = Catalog.validate(catalog, signal)
    assert signal.type == MessageReceived.type()
    assert signal.dataschema == MessageReceived.dataschema()
  end

  test "catalog rejects invalid data and unknown schema identities" do
    catalog = Catalog.new!([MessageReceived])
    signal = MessageReceived.new!(%{"text" => "hello"})

    assert {:error, %{details: %{code: :invalid_data}}} =
             Catalog.validate(catalog, %{signal | data: %{"text" => 1}})

    assert {:error, %{details: %{code: :unknown_dataschema}}} =
             Catalog.validate(catalog, %{signal | dataschema: "urn:jido:unknown:2"})
  end

  test "Bus uses type, source, and subject conjunction and keeps selected order" do
    bus = start_supervised!({Bus, name: unique_name()})
    source = "urn:jido:chat:binding:fixture"
    subject = "room:fixture"

    assert {:ok, _} =
             Bus.subscribe(bus, "jido.chat.baseline.*", selector: [source: source, subject: subject])

    first = MessageReceived.new!(%{"text" => "first"}, subject: subject)
    last = MessageReceived.new!(%{"text" => "last"}, subject: subject)

    excluded = [
      %{first | source: "urn:jido:chat:binding:other"},
      %{first | subject: "room:other"},
      %{first | subject: nil},
      %{first | type: "inventory.stock.changed"}
    ]

    assert {:ok, records} = Bus.publish(bus, [first] ++ excluded ++ [last])
    assert Enum.map(records, & &1.signal) == [first] ++ excluded ++ [last]
    assert_received {:signal, ^first}
    assert_received {:signal, ^last}
    refute_received {:signal, _}
  end

  test "invalid selectors fail before Bus state changes or callbacks run" do
    bus = start_supervised!({Bus, name: unique_name()})
    observer = self()
    callback = fn _ -> send(observer, :predicate_called) end
    before = :sys.get_state(bus)

    for selector <- [
          nil,
          [],
          %{source: "/fixture"},
          [data: %{"text" => "hello"}],
          [extensions: %{}],
          callback,
          {__MODULE__, :predicate, []},
          [source: "/fixture", source: "/other"],
          [subject: nil],
          [source: "contains spaces"],
          [subject: String.duplicate("a", 4_097)]
        ] do
      assert {:error, {:invalid_selector, _}} = Bus.subscribe(bus, "**", selector: selector)
      assert :sys.get_state(bus) == before
    end

    assert {:error, {:invalid_selector, _}} =
             Bus.subscribe(bus, "**", selector: [source: "/fixture"], selector: [subject: "room"])

    assert :sys.get_state(bus) == before
    refute_received :predicate_called
  end

  test "filtered durable subscriptions fail without a stored subscription" do
    bus = start_supervised!({Bus, name: unique_name()})
    before = :sys.get_state(bus)

    assert {:error, {:conflicting_options, [:selector, :durable]}} =
             Bus.subscribe(bus, "**", selector: [subject: "room"], durable: "fixture")

    assert :sys.get_state(bus) == before
  end

  test "the same Bus contract selects an unrelated non-chat family" do
    bus = start_supervised!({Bus, name: unique_name()})

    assert {:ok, _} =
             Bus.subscribe(bus, "inventory.*.changed", selector: [source: "/east", subject: "sku-1"])

    signal = Signal.new!("inventory.stock.changed", %{"count" => 4}, source: "/east", subject: "sku-1")
    assert {:ok, _} = Bus.publish(bus, [signal])
    assert_received {:signal, ^signal}
  end

  defp unique_name, do: Module.concat(__MODULE__, "Bus#{System.unique_integer([:positive])}")
end
