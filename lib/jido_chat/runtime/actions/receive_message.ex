defmodule Jido.Chat.Runtime.Actions.ReceiveMessage do
  @moduledoc "Records one admitted room fact and builds an optional reply."

  use Jido.Action, name: "receive_chat_room_message", schema: Zoi.map()

  alias Jido.Chat.{Message, Post}
  alias Jido.Chat.Runtime.Directives.Receive
  alias Jido.Chat.Runtime.Participant
  alias Jido.Chat.Runtime.Signal.Room.Post, as: PostSignal

  @impl true
  def run(_params, context) do
    signal = context.signal
    state = context.agent_state
    options = context.plugin_inputs[Participant].runtime

    if Enum.any?(state.participation.received, &(&1.id == signal.id)) do
      {:ok, state, []}
    else
      message = Message.from_map(signal.data["message"])

      reply =
        if options.respond == :mentioned and is_nil(message.reply_to_id) and
             options.member in signal.data["mentions"] and options.member != signal.data["author"] do
          id =
            :crypto.hash(
              :sha256,
              :erlang.term_to_binary({options.member, signal.data["room"], signal.id})
            )
            |> Base.url_encode64(padding: false)

          post = Post.text(options.reply_text, reply_to_id: message.id)
          PostSignal.new!(%{"post" => Post.to_map(post), "mentions" => []}, id: "reply-" <> id)
        end

      {:ok, state, [%Receive{message: signal, reply: reply}]}
    end
  end
end
