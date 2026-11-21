defmodule Jido.Chat.Discord.LiveReply do
  @moduledoc false
  use Jido.Action, name: "discord_live_reply", schema: Zoi.map()

  @doc false
  def run(params, context) do
    if String.starts_with?(params["text"] || "", "jido-discord-source-probe:") do
      command =
        Jido.Chat.Signal.Policy.new!(Jido.Chat.Signal.SendMessage, %{
          "client_id" => context.chat.client_id,
          "request_id" => params["item_id"] <> ":reply",
          "room_id" => params["room_id"],
          "reply_to_id" => params["message_id"],
          "text" => "jido-discord-source-reply:" <> params["message_id"]
        })

      {:ok, %{context.agent_state | received_id: params["message_id"]}, [Jido.Agent.Directive.emit(command)]}
    else
      {:ok, context.agent_state}
    end
  end
end

defmodule Jido.Chat.Discord.LiveRecord do
  @moduledoc false
  use Jido.Action, name: "discord_live_record", schema: Zoi.map()

  @doc false
  def run(_params, context) do
    result = context.signal.data["result"] || %{}
    {:ok, %{context.agent_state | reply_id: result["id"] || "", delivery_type: context.signal.type}}
  end
end

defmodule Jido.Chat.Discord.LiveAgent do
  @moduledoc false
  use Jido.Agent, name: "discord_live_agent", plugins: [Jido.Chat.Plugin]

  state do
    schema(
      Jido.Joi.object(%{
        received_id: Zoi.string() |> Zoi.default(""),
        reply_id: Zoi.string() |> Zoi.default(""),
        delivery_type: Zoi.string() |> Zoi.default("")
      })
    )
  end

  chat do
    connection :discord do
      client Jido.Chat.Discord.Adapter, id: "discord-live"
      rooms ["placeholder"]
      commands [Jido.Chat.SendMessage]
      source Jido.Chat.Discord.Source, emit: "jido.chat.message.received"
    end
  end

  routes do
    route("jido.chat.message.received", Jido.Chat.Discord.LiveReply)
    route("jido.chat.command.*", Jido.Chat.Plugin.Execute)
    route("jido.chat.command.send_message.completed", Jido.Chat.Discord.LiveRecord)
    route("jido.chat.command.send_message.failed", Jido.Chat.Discord.LiveRecord)
  end
end
