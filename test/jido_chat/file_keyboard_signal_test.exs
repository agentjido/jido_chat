defmodule Jido.Chat.FileKeyboardSignalTest do
  use ExUnit.Case, async: true
  alias Jido.Chat.Signal.{EditMessage, SendFile, SendMessage}

  defp base, do: %{"client_id" => "bot", "request_id" => "r", "room_id" => "123"}

  test "keyboards are validated JSON values and survive the closed catalog" do
    keyboard = %{
      "rows" => [
        [%{"text" => "Confirm", "value" => "confirm:1"}, %{"text" => "Help", "url" => "https://example.com/help"}]
      ]
    }

    signal = SendMessage.new!(Map.merge(base(), %{"text" => "Choose", "keyboard" => keyboard}))
    assert {:ok, json} = Jido.Signal.Serialization.serialize(signal)
    assert {:ok, ^signal} = Jido.Signal.Catalog.decode(Jido.Chat.catalog(), json)
    assert EditMessage.new!(Map.merge(base(), %{"message_id" => "1", "text" => "Done", "keyboard" => %{"rows" => []}}))

    for invalid <- [
          %{"rows" => [[%{"text" => "Both", "value" => "x", "url" => "https://example.com"}]]},
          %{"rows" => [[%{"text" => "Empty"}]]},
          %{"rows" => [[%{"text" => "Too long", "value" => String.duplicate("é", 33)}]]},
          %{"rows" => [[]]},
          %{"inline_keyboard" => []}
        ] do
      assert {:error, _} = SendMessage.new(Map.merge(base(), %{"text" => "Choose", "keyboard" => invalid}))
    end
  end

  test "SendFile uses one source schema for files, URLs, provider references, and base64 bytes" do
    for source <- [
          %{"client_id" => "bot", "kind" => "file", "id" => "/tmp/test.txt"},
          %{"client_id" => "bot", "kind" => "url", "id" => "https://example.com/test.txt"},
          %{"client_id" => "bot", "kind" => "media", "id" => "telegram://file/1"},
          %{"content_base64" => Base.encode64("bytes"), "filename" => "test.txt"}
        ] do
      signal = SendFile.new!(Map.put(base(), "source", source))
      assert {:ok, json} = Jido.Signal.Serialization.serialize(signal)
      assert {:ok, ^signal} = Jido.Signal.Catalog.decode(Jido.Chat.catalog(), json)
    end

    for source <- [
          %{"content_base64" => "!", "filename" => "test.txt"},
          %{"content_base64" => "", "filename" => "test.txt"}
        ] do
      assert {:error, _} = SendFile.new(Map.put(base(), "source", source))
    end

    assert {:error, _} = SendFile.new(Map.put(base(), "resource_ref", %{}))
  end
end
