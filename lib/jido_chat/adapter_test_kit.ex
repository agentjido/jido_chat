defmodule Jido.Chat.AdapterTestKit do
  @moduledoc """
  Shared protocol version 1 conformance support.

  Every adapter has an explicit native/fallback/unsupported operation matrix.
  Provider fixtures execute through a configured binding and typed request.
  Unsupported features require a typed result assertion; they do not pass by
  skipping a supported test body.
  """

  @doc "Adds protocol and capability-coherence checks and shared typed assertions."
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    adapter = Keyword.fetch!(opts, :adapter)
    async = Keyword.get(opts, :async, true)

    quote do
      use ExUnit.Case, async: unquote(async)
      import Jido.Chat.AdapterTestKit.Assertions
      import Jido.Chat.AdapterTestKit.Factories
      @adapter unquote(adapter)
      test "adapter implements the typed protocol and coherent capabilities" do
        assert_capability_coherence(@adapter)
        assert_unsupported_operations(@adapter)
      end
    end
  end

  @doc "Returns the explicit supported status for a checked operation."
  @spec supported?(module(), atom()) :: boolean()
  def supported?(adapter, operation), do: Jido.Chat.Adapter.capabilities(adapter)[operation] in [:native, :fallback]
end
