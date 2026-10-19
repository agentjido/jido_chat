defmodule Jido.Chat.PartialUpdateSignalTest do
  use ExUnit.Case, async: true

  test "unknown and empty update text remain distinct through the closed native catalog" do
    catalog = Jido.Signal.Catalog.new!(Jido.Chat.signal_definitions())

    for text <- [nil, "", "updated"] do
      signal =
        Jido.Chat.Signal.Policy.new!(Jido.Chat.Signal.MessageUpdated, %{
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

  test "reaction clear retains an unknown previous emoji as required null" do
    data = %{
      "item_id" => "clear-1",
      "delivery_id" => "delivery-1",
      "room_id" => "room-1",
      "message_id" => "message-1",
      "actor_id" => "actor-1",
      "reaction" => nil
    }

    for reaction <- [nil, "👍"] do
      signal = Jido.Chat.Signal.Policy.new!(Jido.Chat.Signal.ReactionRemoved, Map.put(data, "reaction", reaction))
      assert {:ok, json} = Jido.Signal.Serialization.serialize(signal)
      assert {:ok, ^signal} = Jido.Signal.Catalog.decode(Jido.Signal.Catalog.new!(Jido.Chat.signal_definitions()), json)
      assert signal.data["reaction"] == reaction
    end

    for invalid <- [
          Map.delete(data, "reaction"),
          Map.put(data, "reaction", ""),
          Map.put(data, "reaction", 1),
          Map.put(data, "raw", %{})
        ] do
      assert {:error, _} = Jido.Chat.Signal.Policy.new(Jido.Chat.Signal.ReactionRemoved, invalid)
    end

    assert {:error, _} = Jido.Chat.Signal.Policy.new(Jido.Chat.Signal.ReactionAdded, data)
  end

  test "partial updates still reject absent text, unsafe text and undeclared provider fields" do
    data = %{
      "item_id" => "update-1",
      "delivery_id" => "delivery-1",
      "room_id" => "room-1",
      "message_id" => "message-1",
      "text" => nil
    }

    assert {:error, _} = Jido.Chat.Signal.Policy.new(Jido.Chat.Signal.MessageUpdated, Map.delete(data, "text"))
    assert {:error, _} = Jido.Chat.Signal.Policy.new(Jido.Chat.Signal.MessageUpdated, Map.put(data, "text", 42))
    assert {:error, _} = Jido.Chat.Signal.Policy.new(Jido.Chat.Signal.MessageUpdated, Map.put(data, "raw", %{}))
  end
end
