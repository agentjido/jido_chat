defmodule Jido.Chat.Plugin.SourceSpec do
  @moduledoc false
  @type t :: %__MODULE__{
          module: module() | nil,
          options: keyword() | nil,
          emit: String.t() | [String.t()] | nil,
          __spark_metadata__: term()
        }
  defstruct [:module, :options, :emit, :__spark_metadata__]
end
