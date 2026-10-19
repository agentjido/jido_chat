defmodule Jido.Chat.Plugin.Execute do
  @moduledoc """
  Terminal Agent Action for Chat command routes.

  Returns complete Agent state and a Deliver directive. The Plugin runs the SDK
  Action after the turn commits and sends its result Signal back to the Agent.
  """
  use Jido.Action, name: "chat_plugin_execute", schema: Zoi.map()

  def run(_params, context) do
    {:ok, context.agent_state, [%Jido.Chat.Plugin.Deliver{signal: context.signal}]}
  end
end
