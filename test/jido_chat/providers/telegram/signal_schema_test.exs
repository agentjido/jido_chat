defmodule Jido.Chat.Telegram.SignalSchemaTest do
  use ExUnit.Case, async: true
  alias Jido.Chat.Telegram
  alias Telegram.Signal.Schemas

  test "file results reject unsafe paths and negative sizes" do
    ref = %{"client_id" => "telegram", "kind" => "media", "id" => "telegram://file/file-1"}

    for path <- ["photos/a-b_1.jpg", "documents/report.txt"] do
      value = %{"resource_ref" => ref, "file_path" => path, "size" => 0}
      assert {:ok, ^value} = Zoi.parse(Schemas.file_result(), value)
    end

    for path <- ["../secret", "/absolute", "a//b", "a/./b", "https://example.com/a", "a/../b", "a?token=secret"] do
      assert {:error, _} = Zoi.parse(Schemas.file_result(), %{"resource_ref" => ref, "file_path" => path})
    end

    assert {:error, _} = Zoi.parse(Schemas.file_result(), %{"resource_ref" => ref, "file_path" => "a", "size" => -1})
  end

  test "draft room identifiers must be complete integers" do
    for value <- ["123", "-100123"] do
      assert {:ok, ^value} = Zoi.parse(Schemas.numeric_id(), value)
    end

    for value <- ["@channel", "123suffix", ""] do
      assert {:error, _} = Zoi.parse(Schemas.numeric_id(), value)
    end
  end

  test "result schemas enforce provider result shapes" do
    values = [
      {Schemas.poll_result(), %{"id" => "1", "room_id" => "2", "poll_id" => "3"}},
      {Schemas.webhook_result(), %{"url" => "", "pending_update_count" => 0, "has_custom_certificate" => false}},
      {Schemas.user_result(), %{"id" => "1", "is_bot" => true, "username" => "bot", "display_name" => "Bot"}},
      {Schemas.callback_result(), %{"answered" => true, "interaction_id" => "cb"}},
      {Schemas.draft_result(), %{"acknowledged" => true, "draft_id" => 1}},
      {Schemas.updates_result(), %{"delivery_id" => "batch", "signals" => [], "next_offset" => nil}}
    ]

    for {schema, value} <- values do
      assert {:ok, ^value} = Zoi.parse(schema, value)
      assert {:error, _} = Zoi.parse(schema, %{})
      assert {:error, _} = Zoi.parse(schema, Map.put(value, "raw_provider_data", "unexpected"))
    end
  end

  test "all operations point to the Action for that request and are catalog registered" do
    assert Telegram.adapter() == Telegram.Adapter
    routes = Telegram.operations()
    assert length(routes) == 14
    assert Enum.sort(Enum.map(routes, &elem(&1, 1))) == Enum.sort(Telegram.actions())
    catalog = Telegram.catalog()

    for {definition, action} <- routes do
      assert definition == action.signal_definition()
    end

    assert %Jido.Signal.Catalog{} = catalog
  end
end
