defmodule Jido.Chat.SentMessageEditTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{Attachment, FileUpload, Postable, Response, SentMessage}

  defmodule Adapter do
    def channel_type, do: :test
    def capabilities, do: %{edit_attachments: :native}
    def send_message(_, _, _), do: raise("edit created a new message")

    def edit_message(room, id, text, opts) do
      send(self(), {:edit, room, id, text, opts})

      Process.get(
        :edit_result,
        {:ok,
         Response.new(%{
           external_message_id: id,
           external_room_id: room,
           status: :edited,
           metadata: %{media: [%{file_id: "uploaded"}]}
         })}
      )
    end
  end

  defmodule UnsupportedAdapter do
    def capabilities, do: %{edit_attachments: :unsupported}
    def send_message(_, _, _), do: raise("edit created a new message")
    def edit_message(_, _, _, _), do: raise("unsupported edit dispatched")
  end

  defmodule MissingEditAdapter do
    def capabilities, do: %{edit_attachments: :native}
    def send_message(_, _, _), do: raise("edit created a new message")
  end

  test "attachment edit capabilities require an edit callback but remain opt-in" do
    assert :ok = Jido.Chat.Adapter.validate_capabilities(Adapter)
    assert :ok = Jido.Chat.Adapter.validate_capabilities(UnsupportedAdapter)

    assert {:error, {:invalid_capability_matrix, errors}} =
             Jido.Chat.Adapter.validate_capabilities(MissingEditAdapter)

    assert {:edit_attachments, :missing_callback} in errors
  end

  test "attachment payloads are normalized and forwarded to the existing message" do
    for field <- [:files, :attachments] do
      payload = Postable.text("updated", [{field, [%{data: "bytes", filename: "report.txt"}]}])
      assert {:ok, edited} = SentMessage.edit(sent(), payload, token: "override")
      assert_received {:edit, "room", "post", "updated", opts}
      assert [%FileUpload{data: "bytes", filename: "report.txt"}] = opts[:files]
      assert opts[:token] == "override"
      assert edited.id == "post"
      assert [%Attachment{filename: "report.txt"}] = edited.attachments
      assert edited.metadata.media == [%{file_id: "uploaded"}]
      assert edited.metadata.retained == true
    end
  end

  test "attachment edits on restored handles serialize the latest delivery metadata" do
    original = %{sent() | default_opts: []}
    restored = original |> SentMessage.to_map() |> SentMessage.from_map()
    assert restored.metadata["media"] == [%{"file_id" => "old"}]

    payload = Postable.text("updated", files: [%{data: "bytes", filename: "report.txt"}])
    assert {:ok, edited} = SentMessage.edit(restored, payload, token: "override")
    assert edited.id == original.id
    assert edited.metadata.media == [%{file_id: "uploaded"}]
    assert_received {:edit, "room", "post", "updated", _}

    serialized = edited |> SentMessage.to_map() |> Jason.encode!() |> Jason.decode!()
    assert serialized["metadata"]["media"] == [%{"file_id" => "uploaded"}]
    assert serialized["metadata"]["retained"] == true
  end

  test "string-keyed delivery metadata replaces atom-keyed and payload metadata" do
    Process.put(
      :edit_result,
      {:ok,
       Response.new(%{
         external_message_id: "post",
         metadata: %{"media" => [%{"file_id" => "latest"}]}
       })}
    )

    payload = Postable.text("updated", metadata: %{media: [%{file_id: "payload"}]})
    assert {:ok, edited} = SentMessage.edit(sent(), payload)
    refute Map.has_key?(edited.metadata, :media)
    assert edited.metadata["media"] == [%{"file_id" => "latest"}]
    assert edited.metadata.retained == true
    assert SentMessage.to_map(edited)["metadata"]["media"] == [%{"file_id" => "latest"}]
  end

  test "text-only edits preserve attachments and metadata absent from the response" do
    Process.put(:edit_result, {:ok, Response.new(%{external_message_id: "post"})})
    original = sent()

    original = %{
      original
      | response: %{
          original.response
          | metadata: %{"media" => [%{"file_id" => "delivered"}], "filename" => "report.txt"}
        }
    }

    assert {:ok, edited} = SentMessage.edit(original, "updated")
    assert edited.attachments == original.attachments
    assert edited.metadata["filename"] == "report.txt"
    assert edited.metadata["media"] == [%{"file_id" => "delivered"}]
    assert edited.metadata.retained
    refute Map.has_key?(edited.metadata, :media)
    assert_received {:edit, "room", "post", "updated", opts}
    refute Keyword.has_key?(opts, :files)
    assert opts[:previous_metadata] == edited.metadata
  end

  test "explicit response attachments replace or clear the handle independently of media metadata" do
    for attachments <- [[], [%{url: "provider://new", filename: "new.txt"}]],
        key <- [:attachments, "attachments"] do
      Process.put(:edit_result, {:ok, Response.new(%{external_message_id: "post", metadata: %{key => attachments}})})
      original = sent()
      assert {:ok, edited} = SentMessage.edit(original, "updated")
      assert edited.attachments == Attachment.normalize_many(attachments)
      assert_received {:edit, "room", "post", "updated", opts}
      assert opts[:previous_metadata] == original.metadata
    end
  end

  test "sparse replacement invalidates old snapshots through persistence and subsequent edits" do
    for key <- [:attachments, "attachments"] do
      original = sent()
      old = [%{filename: "old.txt", url: "provider://old"}]

      original = %{
        original
        | metadata: Map.put(original.metadata, key, old),
          response: %{original.response | metadata: %{key => old}}
      }

      Process.put(:edit_result, {:ok, Response.new(%{external_message_id: "post", external_room_id: "room"})})
      payload = Postable.text("replacement", files: [%{data: "new", filename: "new.txt"}])

      assert {:ok, edited} = SentMessage.edit(original, payload)
      assert_received {:edit, "room", "post", "replacement", initial_opts}
      assert initial_opts[:previous_metadata][key] == old
      assert [%Attachment{filename: "new.txt"}] = edited.attachments
      refute Map.has_key?(edited.metadata, :attachments)
      refute Map.has_key?(edited.metadata, "attachments")
      assert edited.metadata.retained

      restored = edited |> SentMessage.to_map() |> Jason.encode!() |> Jason.decode!() |> SentMessage.from_map()
      assert {:ok, next} = SentMessage.edit(restored, "text only")
      assert_received {:edit, "room", "post", "text only", next_opts}
      refute Map.has_key?(next_opts[:previous_metadata], :attachments)
      refute Map.has_key?(next_opts[:previous_metadata], "attachments")
      assert next_opts[:previous_metadata]["retained"]
      assert [%Attachment{filename: "new.txt"}] = next.attachments
    end
  end

  test "replacement keeps fresh response snapshots and sparse text edits retain them" do
    for key <- [:attachments, "attachments"],
        snapshot <- [[], [%{filename: "confirmed.txt", url: "provider://confirmed"}]] do
      original = sent()
      original = %{original | response: %{original.response | metadata: %{attachments: original.attachments}}}
      Process.put(:edit_result, {:ok, Response.new(%{external_message_id: "post", metadata: %{key => snapshot}})})
      payload = Postable.text("replacement", files: [%{data: "new", filename: "new.txt"}])
      assert {:ok, edited} = SentMessage.edit(original, payload)
      assert_received {:edit, "room", "post", "replacement", _}
      assert edited.metadata[key] == snapshot
      assert edited.attachments == Attachment.normalize_many(snapshot)

      Process.put(:edit_result, {:ok, Response.new(%{external_message_id: "post"})})
      assert {:ok, next} = SentMessage.edit(edited, "text only")
      assert_received {:edit, "room", "post", "text only", opts}
      assert opts[:previous_metadata][key] == snapshot
      assert next.metadata[key] == snapshot
      assert next.attachments == edited.attachments
    end
  end

  test "unsupported adapters reject attachments before dispatch" do
    original = %{sent() | adapter: UnsupportedAdapter}

    assert {:error, :edit_attachments_unsupported} =
             SentMessage.edit(original, Postable.text("updated", files: ["report.txt"]))

    refute_received {:edit, _, _, _, _}
  end

  test "adapter failures propagate without changing the handle" do
    for reason <- [:timeout, :multiple_attachments_unsupported] do
      Process.put(:edit_result, {:error, reason})

      assert {:error, ^reason} =
               SentMessage.edit(sent(), Postable.text("updated", files: ["report.txt"]))
    end
  end

  test "stream edits remain unsupported" do
    assert {:error, :edit_stream_unsupported} = SentMessage.edit(sent(), %Postable{kind: :stream})
    refute_received {:edit, _, _, _, _}
  end

  defp sent do
    SentMessage.new(%{
      adapter: Adapter,
      response: %{external_message_id: "post", external_room_id: "room"},
      attachments: [%{filename: "old.txt", url: "https://example.com/old.txt"}],
      metadata: %{retained: true, media: [%{file_id: "old"}]},
      default_opts: [token: "default"]
    })
  end
end
