defmodule Jido.Chat.ProviderMediaRuntimeTest do
  use ExUnit.Case, async: false

  alias Jido.Messaging.Runtime

  defmodule Instance do
    use Jido.Messaging, runtime_profile: :core
  end

  defmodule TelegramTransport do
    @behaviour Jido.Chat.Telegram.Transport
    @impl true
    def call(_token, _method, _payload, _opts), do: raise("unexpected provider call")
  end

  defmodule SlackTransport do
    def call(_method, _payload, _opts), do: raise("unexpected provider call")
  end

  setup do
    start_supervised!(Instance)
    :ok
  end

  test "Telegram native photo retains private URL and dimensions through Messaging" do
    {:ok, binding} =
      Jido.Chat.bind(Jido.Chat.Telegram.Adapter,
        id: "telegram-media",
        token: "fixture-token",
        bot_id: 99,
        transport: TelegramTransport
      )

    :ok = Runtime.register_binding(Instance.__jido_messaging__(:runtime), binding)

    payload = %{
      "update_id" => 701,
      "message" => %{
        "message_id" => 42,
        "date" => 1_700_000_000,
        "chat" => %{"id" => -123, "type" => "group", "title" => "Fixture"},
        "from" => %{"id" => 7, "first_name" => "Peer"},
        "caption" => "complete Telegram caption",
        "photo" => [
          %{
            "file_id" => "owned-photo",
            "file_unique_id" => "owned-unique",
            "width" => 40,
            "height" => 30,
            "file_size" => 128
          }
        ]
      }
    }

    {:ok, delivery} = Jido.Chat.normalize_event(binding, payload)
    original = Enum.map(delivery.signals, &Jido.Signal.to_map/1)
    assert {:ok, _} = Instance.accept_delivery(delivery)
    assert {:ok, message} = Instance.get_message_by_external_id(:telegram, binding.id, "42")

    assert Enum.any?(
             message.content,
             &match?(
               %Jido.Chat.Content.Image{
                 url: "telegram://file/owned-photo",
                 width: 40,
                 height: 30
               },
               &1
             )
           )

    assert message.metadata.media.count == 1
    assert message.metadata.media.total_bytes == 128
    assert {:ok, []} = Instance.accept_delivery(delivery)
    assert {:ok, [^message]} = Instance.list_messages(message.room_id)
    assert Enum.map(delivery.signals, &Jido.Signal.to_map/1) == original
  end

  test "Slack native file retains private URL and complete text through Messaging" do
    {:ok, binding} =
      Jido.Chat.bind(Jido.Chat.Slack.Adapter,
        id: "slack-media",
        token: "fixture-token",
        transport: SlackTransport
      )

    :ok = Runtime.register_binding(Instance.__jido_messaging__(:runtime), binding)

    payload = %{
      "type" => "event_callback",
      "event_id" => "EvMedia",
      "event" => %{
        "type" => "message",
        "channel" => "C1",
        "user" => "U1",
        "ts" => "1.01",
        "text" => "complete Slack text",
        "files" => [
          %{
            "id" => "F1",
            "name" => "owned.pdf",
            "mimetype" => "application/pdf",
            "url_private_download" => "https://fixture.invalid/private.pdf",
            "size" => 256
          }
        ]
      }
    }

    {:ok, delivery} = Jido.Chat.normalize_event(binding, payload)
    original = Enum.map(delivery.signals, &Jido.Signal.to_map/1)
    assert {:ok, _} = Instance.accept_delivery(delivery)
    assert {:ok, message} = Instance.get_message_by_external_id(:slack, binding.id, "1.01")

    assert [
             %Jido.Chat.Content.Text{text: "complete Slack text"},
             %Jido.Chat.Content.File{
               url: "https://fixture.invalid/private.pdf",
               filename: "owned.pdf"
             }
           ] = message.content

    assert message.metadata.media.count == 1
    assert {:ok, []} = Instance.accept_delivery(delivery)
    assert {:ok, [^message]} = Instance.list_messages(message.room_id)
    assert Enum.map(delivery.signals, &Jido.Signal.to_map/1) == original
  end
end
