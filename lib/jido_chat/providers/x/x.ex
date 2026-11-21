defmodule Jido.Chat.X do
  @moduledoc "X/Twitter Direct Messages adapter for `Jido.Chat`."

  alias Jido.Chat.X.Adapter

  @doc "Returns the canonical X adapter module."
  def adapter, do: Adapter

  @doc "Returns provider-specific request and Action pairs."
  def operations, do: []

  @doc "Returns the incoming facts normalized by X."
  defdelegate event_definitions, to: Adapter
end
