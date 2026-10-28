defmodule Jido.Chat.Runtime.Bridge.Mapping do
  @moduledoc false
  @type t :: %__MODULE__{
          name: atom() | nil,
          external_room: String.t() | nil,
          room: String.t() | Jido.Agent.Ref.t() | nil,
          direction: :inbound | :outbound | :both | nil,
          __spark_metadata__: term()
        }
  defstruct [:name, :external_room, :room, :direction, :__spark_metadata__]
end
