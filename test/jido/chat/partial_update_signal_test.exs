defmodule Jido.Chat.PartialUpdateSignalTest do
  use ExUnit.Case, async: true

  test "unknown and empty update text remain distinct through the closed native catalog" do
    catalog = Jido.Signal.Catalog.new!(Jido.Chat.signal_definitions())

    for text <- [nil, "", "updated"] do
      signal =
        Jido.Chat.Signal.MessageUpdated.new!(%{
          "item_id" => "update-1",
          "delivery_id" => "delivery-1",
          "room_id" => "room-1",
          "message_id" => "message-1",
          "text" => text
        })

      assert {:ok, json} = Jido.Signal.Serialization.serialize(signal)
      assert {:ok, ^signal} = Jido.Signal.Catalog.decode(catalog, json)
      assert signal.data["text"] == text
    end
  end

  test "partial updates still reject absent text, unsafe text and undeclared provider fields" do
    data = %{
      "item_id" => "update-1",
      "delivery_id" => "delivery-1",
      "room_id" => "room-1",
      "message_id" => "message-1",
      "text" => nil
    }

    assert {:error, _} = Jido.Chat.Signal.MessageUpdated.new(Map.delete(data, "text"))
    assert {:error, _} = Jido.Chat.Signal.MessageUpdated.new(Map.put(data, "text", 42))
    assert {:error, _} = Jido.Chat.Signal.MessageUpdated.new(Map.put(data, "raw", %{}))
  end
end
