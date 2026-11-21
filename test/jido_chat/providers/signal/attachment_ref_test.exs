defmodule Jido.Chat.Signal.AttachmentRefTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Signal.AttachmentRef

  test "keeps local attachment order for atom and string path maps" do
    assert {:ok, ["/tmp/one", "/tmp/two", "/tmp/three"]} =
             AttachmentRef.refs([
               %{path: "/tmp/one"},
               %{"path" => "/tmp/two"},
               "/tmp/three"
             ])
  end

  test "builds data URIs and keeps existing data URIs" do
    assert {:ok, "data:text/plain;filename=note.txt;base64,bm90ZQ=="} =
             AttachmentRef.ref(%{
               data: "bm90ZQ==",
               media_type: "text/plain",
               filename: "note.txt"
             })

    assert {:ok, "data:application/octet-stream;filename=attachment;base64,YQ=="} =
             AttachmentRef.ref(%{"data" => "YQ=="})

    assert {:ok, "data:image/png;base64,AAAA"} =
             AttachmentRef.ref(%{data: "data:image/png;base64,AAAA"})
  end

  test "rejects remote and invalid attachments" do
    for attachment <- [
          %{url: "https://example.test/a"},
          %{"url" => "http://example.test/b"},
          "https://example.test/c"
        ] do
      assert {:error, {:unsupported_remote_attachment, _}} = AttachmentRef.ref(attachment)
    end

    assert {:error, {:invalid_attachment, :invalid}} = AttachmentRef.ref(:invalid)
    assert {:error, {:invalid_attachments, :invalid}} = AttachmentRef.refs(:invalid)

    assert {:error, {:invalid_attachment, :invalid}} =
             AttachmentRef.refs(["/tmp/ok", :invalid])
  end
end
