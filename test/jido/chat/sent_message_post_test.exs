defmodule Jido.Chat.SentMessagePostTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{Attachment, ChannelRef, Postable, PostPayload, Response, Thread}

  defmodule Adapter do
    def channel_type, do: :test
    def send_message(_, _, _), do: raise("unexpected text-only dispatch")
    def capabilities, do: %{post_message: :native, multi_file: :native}

    def post_message(room, _payload, opts) do
      {:ok, Response.new(%{external_message_id: "first", external_room_id: room, metadata: opts[:response_metadata]})}
    end
  end

  test "capability matrix is coherent" do
    assert :ok = Jido.Chat.Adapter.validate_capabilities(Adapter)
  end

  for entry <- [Thread, ChannelRef] do
    @entry entry

    test "#{entry} keeps only the first post's attachments after split delivery" do
      first = [%{url: "https://files.test/a", filename: "a.txt"}]
      second = [%{url: "https://files.test/b", filename: "b.txt"}]

      report = %{
        confirmation: :confirmed,
        messages: [
          %{message_id: "first", metadata: %{attachments: first}},
          %{message_id: "second", metadata: %{attachments: second}}
        ]
      }

      assert {:ok, sent} = post(@entry, %{attachments: first, delivery_report: report})
      assert sent.id == "first"
      assert sent.attachments == Attachment.normalize_many(first)
      assert sent.response.metadata.delivery_report == report
    end

    test "#{entry} excludes rejected uploads from its handle" do
      delivered = [%{url: "https://files.test/a", filename: "a.txt"}]
      report = %{confirmation: :partial, failed_files: [%{filename: "b.txt", reason: :file_too_large}]}
      assert {:ok, sent} = post(@entry, %{"attachments" => delivered, "delivery_report" => report})
      assert sent.attachments == Attachment.normalize_many(delivered)
      assert sent.response.metadata["delivery_report"] == report
    end

    test "#{entry} respects an empty snapshot and falls back only when absent" do
      for key <- [:attachments, "attachments"] do
        assert {:ok, sent} = post(@entry, %{key => []})
        assert sent.attachments == []
      end

      assert {:ok, sent} = post(@entry, %{})
      assert sent.attachments == payload() |> Postable.to_payload() |> PostPayload.outbound_attachments()
    end
  end

  defp payload do
    Postable.text("files", files: [%{data: "a", filename: "a.txt"}, %{data: "b", filename: "b.txt"}])
  end

  defp post(entry, metadata) do
    target =
      case entry do
        Thread -> Thread.new(%{id: "room", adapter: Adapter, adapter_name: :test, external_room_id: "room"})
        ChannelRef -> ChannelRef.new(%{id: "room", adapter: Adapter, adapter_name: :test, external_id: "room"})
      end

    entry.post(target, payload(), response_metadata: metadata)
  end
end
