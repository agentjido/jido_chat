defmodule Jido.Chat.AdapterTestKit do
  @moduledoc """
  Reusable ExUnit support for independent `Jido.Chat.Adapter` packages.

  Use this module in an adapter test module. It adds baseline tests for the
  capability matrix and stable unsupported results. It also imports the
  canonical factories and shared assertions.

      defmodule MyAdapter.ConformanceTest do
        use Jido.Chat.AdapterTestKit, adapter: MyAdapter, async: true
      end

  Provider-specific tests can use `capability_test/3`. The test body runs only
  when the adapter declares the capability as `:native` or `:fallback`.
  """

  alias Jido.Chat.Adapter

  @doc "Adds provider-free adapter conformance tests and shared test helpers."
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    adapter = Keyword.fetch!(opts, :adapter)
    async = Keyword.get(opts, :async, true)

    quote do
      use ExUnit.Case, async: unquote(async)

      import Jido.Chat.AdapterTestKit, only: [capability_test: 3]
      import Jido.Chat.AdapterTestKit.Assertions
      import Jido.Chat.AdapterTestKit.Factories

      @adapter unquote(adapter)

      test "adapter capability declarations are coherent" do
        assert_capability_coherence(@adapter)
      end

      test "adapter operations match declared support" do
        assert_unsupported_operations(@adapter)
      end
    end
  end

  @doc """
  Defines a provider test that runs only when the adapter supports a capability.

      capability_test :edit_message, "normalizes the provider edit result" do
        result = Jido.Chat.Adapter.edit_message(@adapter, "room", "message", "new text")
        assert_capability_result(@adapter, :edit_message, result)
      end
  """
  @spec capability_test(atom(), String.t(), keyword()) :: Macro.t()
  defmacro capability_test(capability, description, do: block) do
    quote do
      test "#{unquote(capability)}: #{unquote(description)}" do
        if Jido.Chat.AdapterTestKit.supported?(@adapter, unquote(capability)) do
          unquote(block)
        else
          :ok
        end
      end
    end
  end

  @doc "Returns true when a capability is native or has a core fallback."
  @spec supported?(module(), atom()) :: boolean()
  def supported?(adapter, capability) when is_atom(adapter) and is_atom(capability) do
    Adapter.capabilities(adapter)[capability] in [:native, :fallback]
  end
end
