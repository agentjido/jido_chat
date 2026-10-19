defmodule Jido.Chat.Error do
  @moduledoc """
  A provider operation error with a safe failure Signal.

  `signal.data["outcome"]` distinguishes a call that did not start, a rejected
  call, and an unknown outcome. The host owns retry and recovery policy.
  Raw provider errors and credentials are not retained.
  """
  use Splode.Error, class: :unknown, fields: [:code, :signal]
  @type t :: %__MODULE__{code: atom(), signal: Jido.Signal.t()}
  @impl true
  def message(error), do: "Chat operation failed: #{error.code}"
end
