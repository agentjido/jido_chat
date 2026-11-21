defmodule Jido.Chat.Signal.AdapterTest do
  use Jido.Chat.AdapterTestKit, adapter: Jido.Chat.Signal.Adapter

  alias Jido.Chat.Client
  alias Jido.Chat.Signal, as: SignalPackage
  alias Jido.Chat.Signal.{Adapter, Operations}
  alias Jido.Signal.Codec

  defmodule FakeTransport do
    @behaviour Jido.Chat.Signal.Transport

    @impl true
    def send_message(account, target, text, opts) do
      if pid = opts[:test_pid], do: send(pid, {:signal_send, account, target, text, opts})

      case opts[:provider_result] do
        :atom_key -> {:ok, %{timestamp: 1_776_000_001}}
        :invalid -> {:ok, %{}}
        :error -> {:error, :provider_down}
        _ -> {:ok, %{"timestamp" => 1_776_000_000}}
      end
    end

    @impl true
    def receive_messages(_account, _opts), do: {:ok, []}
  end

  setup do
    client =
      Client.new!(Adapter,
        id: "signal-test",
        transport: FakeTransport,
        credentials: %{account: "+15555550101"},
        config: [test_pid: self()]
      )

    %{client: client}
  end

  test "sends text and inline files through public Chat Actions", %{client: client} do
    assert {:ok, sent} = Jido.Chat.send_text(client, "+15555550100", "hello")
    assert sent.data["result"]["id"] == "1776000000"
    assert_received {:signal_send, "+15555550101", "+15555550100", "hello", opts}
    refute Keyword.has_key?(opts, :account)
    refute Keyword.has_key?(opts, :credentials)

    source = %{"content_base64" => Base.encode64("report"), "filename" => "report.txt"}

    assert {:ok, file} =
             Jido.Chat.send_file(client, "+15555550100", source, caption: "file caption")

    assert file.data["result"]["id"] == "1776000000"
    assert_received {:signal_send, "+15555550101", "+15555550100", "file caption", opts}
    assert [%{data: encoded, filename: "report.txt"}] = opts[:attachments]
    assert encoded == Base.encode64("report")
  end

  test "keeps reply and thread options private and accepts resource references", %{client: client} do
    assert {:ok, sent} =
             Jido.Chat.send_text(client, "+15555550100", "reply",
               reply_to_id: "1775999999",
               thread_id: "thread-1"
             )

    assert sent.data["result"]["reply_to_id"] == "1775999999"
    assert sent.data["result"]["thread_id"] == "thread-1"

    assert_received {:signal_send, _, _, "reply", opts}
    assert opts[:reply_to_id] == "1775999999"
    assert opts[:thread_id] == "thread-1"

    source = %{"kind" => "file", "id" => "/tmp/report.txt"}

    assert {:ok, _} =
             Operations.invoke(
               :send_file,
               client,
               %{
                 data: %{
                   "room_id" => "+15555550100",
                   "source" => source,
                   "caption" => nil
                 }
               },
               []
             )

    assert_received {:signal_send, _, _, "", file_opts}
    assert file_opts[:attachments] == ["/tmp/report.txt"]
  end

  test "reports unsupported input and provider failures", %{client: client} do
    assert {:error, {:not_attempted, :unsupported}} =
             Operations.invoke(:unknown, client, %{data: %{}}, [])

    assert {:error, {:not_attempted, :unsupported}} =
             Operations.invoke(:send_message, :invalid_client, %{data: %{}}, [])

    invalid_file = %{
      data: %{
        "room_id" => "+15555550100",
        "source" => %{"kind" => "file", "id" => "https://example.test/file.txt"}
      }
    }

    assert {:error, :invalid_file_source} =
             Operations.invoke(:send_file, client, invalid_file, [])

    request = %{data: %{"room_id" => "+15555550100", "text" => "hello"}}

    assert {:ok, %{"id" => "1776000001"}} =
             Operations.invoke(
               :send_message,
               %{client | config: [provider_result: :atom_key]},
               request,
               []
             )

    assert {:error, :invalid_provider_result} =
             Operations.invoke(
               :send_message,
               %{client | config: [provider_result: :invalid]},
               request,
               []
             )

    assert {:error, :provider_down} =
             Operations.invoke(
               :send_message,
               %{client | config: [provider_result: :error]},
               request,
               []
             )
  end

  test "normalizes messages, quotes, groups, and attachment references", %{client: client} do
    payload =
      message(1_776_000_000, "hello")
      |> put_in(["envelope", "dataMessage", "groupInfo"], %{"groupId" => "group/1"})
      |> put_in(["envelope", "dataMessage", "quote"], %{"id" => 1_775_999_999})
      |> put_in(["envelope", "dataMessage", "attachments"], [
        %{"contentType" => "image/png", "filename" => "image.png", "size" => 123}
      ])

    assert {:ok, first} = Jido.Chat.normalize(client, payload)
    assert {:ok, second} = Jido.Chat.normalize(client, payload)
    assert first.id == second.id
    assert [signal] = first.signals
    assert signal.type == "jido.chat.message.received"
    assert signal.data["room_id"] == "group:group/1"
    assert signal.data["thread_id"] == "group/1"
    assert signal.data["reply_to_id"] == "1775999999"
    assert [%{"kind" => "image", "resource_ref" => reference}] = signal.data["media"]
    assert reference["client_id"] == client.id
    refute Jason.encode!(Codec.to_map(signal)) =~ "\"size\""
  end

  test "keeps stable ordered facts and reports invalid provider items", %{client: client} do
    input = [message(1, "first"), nil, message(2, "last")]
    assert {:ok, first} = Jido.Chat.normalize(client, input)
    assert {:ok, second} = Jido.Chat.normalize(client, input)
    assert first.id == second.id

    assert Enum.map(first.signals, & &1.type) == [
             "jido.chat.message.received",
             "jido.chat.normalization.failed",
             "jido.chat.message.received"
           ]

    assert Enum.map(first.signals, & &1.data["item_id"]) ==
             Enum.map(second.signals, & &1.data["item_id"])
  end

  test "normalizes sent messages and supported JSON-RPC envelope shapes", %{client: client} do
    sent = %{
      "params" => %{
        "result" => %{
          "envelope" => %{
            "sourceNumber" => "+15555550101",
            "syncMessage" => %{
              "sentMessage" => %{
                "destinationNumber" => "+15555550100",
                "timestamp" => "1776000000",
                "message" => "sent"
              }
            }
          }
        }
      }
    }

    assert {:ok, delivery} = Jido.Chat.normalize(client, sent)
    assert [signal] = delivery.signals
    assert signal.data["room_id"] == "+15555550100"
    assert signal.data["sender"]["is_self"] == true
    refute Map.has_key?(signal.data, "timestamp")

    received = %{"params" => message(2, "received")}
    assert {:ok, delivery} = Jido.Chat.normalize(client, received)
    assert [signal] = delivery.signals
    assert signal.data["text"] == "received"
  end

  test "classifies attachment media and invalid group messages", %{client: client} do
    attachments = [
      %{"contentType" => "audio/ogg; codecs=opus", "filename" => "voice.ogg"},
      %{"content_type" => "video/mp4", "fileName" => "clip.mp4"},
      %{"contentType" => "invalid", "filename" => "photo.JPG"},
      %{"filename" => "report.txt"},
      %{}
    ]

    payload =
      put_in(message(3, "attachments")["envelope"]["dataMessage"]["attachments"], attachments)

    assert {:ok, delivery} = Jido.Chat.normalize(client, payload)
    assert [signal] = delivery.signals

    assert Enum.map(signal.data["media"], & &1["kind"]) == [
             "audio",
             "video",
             "image",
             "file",
             "file"
           ]

    invalid_group =
      put_in(message(4, "legacy group")["envelope"]["dataMessage"]["groupV2"], %{})

    assert {:ok, delivery} = Jido.Chat.normalize(client, invalid_group)
    assert [failure] = delivery.signals
    assert failure.data["code"] == "invalid_item"
    assert failure.data["provider_kind"] == "message"
  end

  test "enforces delivery limits and canonicalizes struct input", %{client: client} do
    assert {:error, %Jido.Chat.Errors.Contract{code: :signal_too_large}} =
             Jido.Chat.normalize(client, message(5, String.duplicate("x", 300_000)))

    assert {:ok, delivery} = Jido.Chat.normalize(client, %URI{scheme: "signal"})
    assert [failure] = delivery.signals
    assert failure.data["code"] == "unsupported_item"

    large_stamp = message(9_999_999_999_999_999_999, "future")
    assert {:ok, delivery} = Jido.Chat.normalize(client, large_stamp)
    assert [signal] = delivery.signals
    refute Map.has_key?(signal.data, "timestamp")

    assert {:error, _} = Jido.Chat.normalize(client, :invalid)
  end

  test "exposes adapter events and the unsupported request boundary", %{client: client} do
    assert SignalPackage.adapter() == Adapter

    assert SignalPackage.event_definitions() == [
             Jido.Chat.Signal.MessageReceived,
             Jido.Chat.Signal.NormalizationFailed
           ]

    assert {:error, {:not_attempted, :unsupported}} =
             Adapter.invoke(client, %{type: "unknown"}, [])
  end

  defp message(stamp, text) do
    %{
      "envelope" => %{
        "sourceNumber" => "+15555550100",
        "sourceName" => "Tester",
        "timestamp" => stamp,
        "dataMessage" => %{"timestamp" => stamp, "message" => text}
      }
    }
  end
end
