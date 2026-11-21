defmodule Jido.Chat.Signal do
  @moduledoc "Signal adapter for `Jido.Chat` using `signal-cli`."

  alias Jido.Chat.Signal.Adapter

  @doc "Returns the canonical Signal adapter module."
  def adapter, do: Adapter

  @doc "Returns the incoming facts normalized by Signal."
  defdelegate event_definitions, to: Adapter
end
