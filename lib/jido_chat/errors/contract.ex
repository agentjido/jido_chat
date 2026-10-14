defmodule Jido.Chat.Errors.Contract do
  @moduledoc """
  A public Signal contract error.

  `code` identifies the rejected contract condition. `field` is an optional
  field name. The error does not retain provider payloads or private resources.
  """

  use Splode.Error, class: :validation, fields: [:code, :field]

  @typedoc "One rejected public contract condition without private input data."
  @type t :: %__MODULE__{code: atom() | nil, field: atom() | nil}

  @impl true
  def message(%__MODULE__{code: code}), do: "Signal contract rejected: #{code}"
end
