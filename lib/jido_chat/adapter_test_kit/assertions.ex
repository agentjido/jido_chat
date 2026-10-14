defmodule Jido.Chat.AdapterTestKit.Assertions do
  @moduledoc "Assertions for the protocol version 1 typed provider boundary."
  import ExUnit.Assertions

  @doc "Asserts the exact implemented protocol and coherent native callbacks."
  @spec assert_capability_coherence(module()) :: :ok
  def assert_capability_coherence(adapter) do
    assert adapter.signal_protocol() == 1
    assert function_exported?(adapter, :configure_binding, 1)
    assert function_exported?(adapter, :normalize_event, 2)
    assert :ok = Jido.Chat.Adapter.validate_capabilities(adapter)
  end

  @doc "Asserts that every unsupported row has an explicit checked status."
  @spec assert_unsupported_operations(module()) :: :ok
  def assert_unsupported_operations(adapter) do
    assert {:ok, matrix} = Jido.Chat.Operations.Capabilities.read(adapter)

    for {_type, {_module, operation, _fields, _shape, _schema}} <- Jido.Chat.Operations.Definitions.all() do
      assert matrix[operation] in [:native, :fallback, :unsupported]
    end

    :ok
  end

  @doc "Asserts a registered completion/failure Signal without a private result projection."
  @spec assert_operation_result(term()) :: Jido.Signal.t()
  def assert_operation_result(result) do
    assert {:ok, %Jido.Signal{} = signal} = result
    assert signal.type in [Jido.Chat.Signal.OperationCompleted.type(), Jido.Chat.Signal.OperationFailed.type()]

    assert {:ok, ^signal} =
             Jido.Signal.Catalog.validate(Jido.Signal.Catalog.new!(Jido.Chat.signal_definitions()), signal)

    signal
  end

  @doc "Asserts a lossless native Signal JSON/Catalog round trip."
  @spec assert_json_round_trip(Jido.Signal.t()) :: :ok
  def assert_json_round_trip(signal) do
    assert {:ok, json} = Jido.Signal.Serialization.serialize(signal)
    assert {:ok, ^signal} = Jido.Signal.Catalog.decode(Jido.Signal.Catalog.new!(Jido.Chat.signal_definitions()), json)
    :ok
  end

  @doc "Asserts a fully validated ordered normalized delivery."
  @spec assert_delivery(Jido.Chat.Binding.t(), term()) :: Jido.Chat.Delivery.t()
  def assert_delivery(binding, result) do
    assert {:ok, %Jido.Chat.Delivery{} = delivery} = result
    assert {:ok, ^delivery} = Jido.Chat.Delivery.validate(binding, delivery)
    delivery
  end
end
