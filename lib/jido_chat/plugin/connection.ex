defmodule Jido.Chat.Plugin.Connection do
  @moduledoc false
  @type t :: %__MODULE__{
          name: atom() | nil,
          client: Jido.Chat.Plugin.ClientSpec.t() | nil,
          rooms: term(),
          source: Jido.Chat.Plugin.SourceSpec.t() | nil,
          commands: [module()] | nil,
          __spark_metadata__: term()
        }
  defstruct [:name, :client, :rooms, :source, :commands, :__spark_metadata__]
end
