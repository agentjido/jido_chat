defmodule Jido.Chat.AdapterTestKit.Assertions do
  @moduledoc "Assertions for the stateless typed provider boundary."
  import ExUnit.Assertions

  @doc "Asserts the exact implemented protocol and coherent native callbacks."
  @spec assert_capability_coherence(module()) :: :ok
  def assert_capability_coherence(adapter) do
    assert Code.ensure_loaded?(adapter)
    assert function_exported?(adapter, :invoke, 3)
    assert function_exported?(adapter, :normalize, 3)
    assert is_map(adapter.capabilities())
    assert :ok = Jido.Chat.Adapter.validate_capabilities(adapter)
    :ok
  end

  @doc "Executes every unsupported core request and requires a typed, not-attempted failure."
  @spec assert_unsupported_operations(module() | Jido.Chat.Client.t()) :: :ok
  def assert_unsupported_operations(%Jido.Chat.Client{} = client) do
    matrix = Jido.Chat.capabilities(client)

    for {_type, {_module, operation, _fields, _shape, _schema}} <- Jido.Chat.Operations.Definitions.all(),
        matrix[operation] == :unsupported do
      request = Jido.Chat.AdapterTestKit.Factories.operation_request(client, operation)
      failed = assert_operation_failure(Jido.Chat.execute(client, request), Jido.Chat.catalog(client))
      assert failed.data["code"] == "unsupported"
      assert failed.data["outcome"] == "not_attempted"
    end

    :ok
  end

  def assert_unsupported_operations(adapter),
    do: assert_unsupported_operations(Jido.Chat.Client.new!(adapter, id: "adapter-test-kit"))

  @doc "Asserts a registered Action completion from Exec or the Chat convenience API."
  @spec assert_operation_success(term(), Jido.Signal.Catalog.t()) :: Jido.Signal.t()
  def assert_operation_success(result, catalog \\ Jido.Chat.catalog())

  def assert_operation_success({:ok, %{signal: %Jido.Signal{} = signal}}, catalog),
    do: assert_operation_success({:ok, signal}, catalog)

  def assert_operation_success(result, catalog) do
    assert {:ok, %Jido.Signal{} = signal} = result
    assert String.ends_with?(signal.type, ".completed")
    assert {:ok, ^signal} = Jido.Signal.Catalog.validate(catalog, signal)
    signal
  end

  @doc "Asserts a registered Action failure carried by the public Chat error."
  @spec assert_operation_failure(term(), Jido.Signal.Catalog.t()) :: Jido.Signal.t()
  def assert_operation_failure(result, catalog \\ Jido.Chat.catalog()) do
    assert {:error, %Jido.Chat.Error{signal: %Jido.Signal{} = signal}} = result
    assert String.ends_with?(signal.type, ".failed")
    assert {:ok, ^signal} = Jido.Signal.Catalog.validate(catalog, signal)
    signal
  end

  @doc "Asserts a lossless native Signal JSON/Catalog round trip."
  @spec assert_json_round_trip(Jido.Signal.t(), Jido.Signal.Catalog.t()) :: :ok
  def assert_json_round_trip(signal, catalog \\ Jido.Chat.catalog()) do
    assert {:ok, json} = Jido.Signal.Serialization.serialize(signal)
    assert {:ok, ^signal} = Jido.Signal.Catalog.decode(catalog, json)
    :ok
  end

  @doc "Asserts a fully validated ordered normalized delivery."
  @spec assert_delivery(Jido.Chat.Client.t(), term()) :: Jido.Chat.Delivery.t()
  def assert_delivery(client, result) do
    assert {:ok, %Jido.Chat.Delivery{} = delivery} = result
    assert {:ok, ^delivery} = Jido.Chat.Delivery.validate(client, delivery)
    delivery
  end
end
