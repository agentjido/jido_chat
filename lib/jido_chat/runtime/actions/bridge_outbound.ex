defmodule Jido.Chat.Runtime.Actions.BridgeOutbound do
  @moduledoc "Translates one admitted local room message into provider work."

  use Jido.Action, name: "chat_bridge_outbound", schema: Zoi.map()

  alias Jido.Chat.Message
  alias Jido.Chat.Runtime.Bridge
  alias Jido.Chat.Runtime.Directives.RelayOutbound

  @impl true
  def run(_params, context) do
    runtime = context.plugin_inputs[Bridge].runtime
    message = Message.from_map(context.signal.data["message"])

    directives =
      if same_origin?(runtime, context.signal, message) do
        []
      else
        Enum.map(runtime.mappings, fn mapping ->
          request_id = request_id(runtime.account_id, mapping.name, message.id)

          data = %{
            "client_id" => runtime.client_id,
            "request_id" => request_id,
            "room_id" => mapping.external_room,
            "text" => Message.fallback_text(message)
          }

          data =
            case runtime.reply_links[mapping.name] do
              nil -> data
              external_id -> Map.put(data, "reply_to_id", external_id)
            end

          command = Jido.Chat.Signal.SendMessage.new!(data)

          work = %{
            id: request_id,
            kind: :outbound,
            account_id: runtime.account_id,
            mapping: mapping.name,
            local_message_id: message.id,
            external_room_id: mapping.external_room,
            signal: command
          }

          %RelayOutbound{work: work}
        end)
      end

    {:ok, context.agent_state, directives}
  end

  defp same_origin?(runtime, signal, message) do
    origin = message.metadata["jido_chat_origin"] || %{}
    signal.data["author"] == runtime.account_ref or origin["account_id"] == runtime.account_id
  end

  defp request_id(account_id, mapping, message_id) do
    value = :erlang.term_to_binary({account_id, mapping, message_id})
    "bridge-outbound/" <> Base.url_encode64(:crypto.hash(:sha256, value), padding: false)
  end
end
