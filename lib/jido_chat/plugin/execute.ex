defmodule Jido.Chat.Plugin.Execute do
  @moduledoc """
  Terminal Agent Action for Chat command routes.

  Returns complete Agent state and a Deliver directive. The Plugin runs the SDK
  Action after the turn commits and sends its result Signal back to the Agent.
  """
  use Jido.Action, name: "chat_plugin_execute", schema: Zoi.map()

  def run(_params, context) do
    {cause, extensions} = Map.pop(context.signal.extensions, "jidocausationid")
    extensions = if cause, do: Map.put(extensions, "causationid", cause), else: extensions
    signal = %{context.signal | extensions: extensions}
    {:ok, context.agent_state, [%Jido.Chat.Plugin.Deliver{signal: signal}]}
  end
end
