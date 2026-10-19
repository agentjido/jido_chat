defmodule Jido.Chat.Plugin.Deliver do
  @moduledoc "Post-commit Chat I/O request owned by the Chat Plugin."
  use Jido.Agent.Directive
  @enforce_keys [:signal]
  @type t :: %__MODULE__{signal: Jido.Signal.t()}
  defstruct [:signal]

  @impl true
  def validate(%__MODULE__{signal: %Jido.Signal{} = _signal} = directive) do
    {:ok, directive}
  end
end
