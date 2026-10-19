defmodule Jido.Chat.Plugin.ClientSpec do
  @moduledoc false
  @type t :: %__MODULE__{
          adapter: module() | nil,
          id: String.t() | nil,
          credentials: map() | nil,
          config: keyword() | nil,
          transport: module() | nil,
          __spark_metadata__: term()
        }
  defstruct [:adapter, :id, :credentials, :config, :transport, :__spark_metadata__]
end
