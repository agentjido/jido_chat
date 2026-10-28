defmodule Jido.Chat.Runtime.Actions.BridgeInbound do
  @moduledoc "Translates one admitted provider message into local room work."

  use Jido.Action, name: "chat_bridge_inbound", schema: Zoi.map()

  alias Jido.Chat.{Actor, Content, FileSource, Media, Post, ResourceRef}
  alias Jido.Chat.Runtime.Bridge
  alias Jido.Chat.Runtime.Directives.RelayInbound
  alias Jido.Chat.Runtime.Signal.Room.Post, as: PostSignal

  @impl true
  def run(_params, context) do
    runtime = context.plugin_inputs[Bridge].runtime

    if runtime.ignore do
      {:ok, context.agent_state, []}
    else
      signal = context.signal
      local_id = stable_id("in", runtime.account_id, runtime.mapping.name, signal.data["message_id"])
      actor = Actor.new(signal.data["sender"])

      metadata = %{
        "jido_chat_origin" => %{
          "account_id" => runtime.account_id,
          "client_id" => runtime.client_id,
          "external_room_id" => runtime.mapping.external_room,
          "external_message_id" => signal.data["message_id"],
          "actor" => Actor.to_map(actor)
        }
      }

      post =
        Post.new(%{
          content: content(signal.data),
          thread_id: runtime.thread_local,
          reply_to_id: runtime.reply_to_local,
          mentions: signal.data["mentions"] || [],
          metadata: metadata
        })

      room_signal =
        PostSignal.new!(
          %{"post" => Post.to_map(post), "mentions" => post.mentions},
          id: local_id
        )

      link = %{
        account_id: runtime.account_id,
        mapping: runtime.mapping.name,
        local_message_id: local_id,
        external_room_id: runtime.mapping.external_room,
        external_message_id: signal.data["message_id"],
        direction: :inbound,
        provider_actor: Actor.to_map(actor),
        external_thread_id: signal.data["thread_id"]
      }

      work = %{
        id: "bridge-inbound/" <> local_id,
        kind: :inbound,
        account_id: runtime.account_id,
        mapping: runtime.mapping.name,
        room: runtime.mapping.room,
        signal: room_signal,
        link: link
      }

      {:ok, context.agent_state, [%RelayInbound{work: work}]}
    end
  end

  defp content(data) do
    text = if data["text"] == "" and data["media"] not in [nil, []], do: [], else: [Content.text(data["text"])]
    text ++ Enum.map(data["media"] || [], &media_content/1)
  end

  defp media_content(value) do
    reference = ResourceRef.new(value["resource_ref"])

    media =
      Media.new(%{
        kind: value["kind"],
        source:
          FileSource.reference(reference,
            filename: value["name"],
            media_type: value["media_type"]
          ),
        name: value["name"],
        media_type: value["media_type"],
        caption: value["caption"],
        width: value["width"],
        height: value["height"],
        duration: value["duration"],
        metadata: value["metadata"] || %{}
      })

    Content.media(media)
  end

  defp stable_id(prefix, account_id, mapping, source_id) do
    value = :erlang.term_to_binary({account_id, mapping, source_id})
    prefix <> "-" <> Base.url_encode64(:crypto.hash(:sha256, value), padding: false)
  end
end
