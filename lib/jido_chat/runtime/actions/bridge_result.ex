defmodule Jido.Chat.Runtime.Actions.BridgeResult do
  @moduledoc "Records one correlated provider result in Runtime storage."

  use Jido.Action, name: "chat_bridge_result", schema: Zoi.map()

  alias Jido.Chat.Runtime.Bridge
  alias Jido.Chat.Runtime.Directives.CompleteOutbound

  @impl true
  def run(_params, context) do
    runtime = context.plugin_inputs[Bridge].runtime

    directive = %CompleteOutbound{
      request_id: runtime.request_id,
      outcome: runtime.outcome,
      result: context.signal.data
    }

    {:ok, context.agent_state, [directive]}
  end
end
