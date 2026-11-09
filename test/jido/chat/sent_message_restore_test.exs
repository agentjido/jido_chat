defmodule Jido.Chat.SentMessageRestoreTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{ChannelRef, Postable, Response, SentMessage, Thread}

  defmodule Transport do
    def edit(room, id, text, opts) do
      send(self(), {:edited, room, id, text, opts})

      {:ok,
       Response.new(%{
         external_message_id: id,
         external_room_id: room,
         channel_type: :test,
         status: :edited,
         metadata: %{attachments: [%{url: "test://file/a", filename: "a.txt"}]}
       })}
    end
  end

  defmodule Adapter do
    def channel_type, do: :test

    def capabilities,
      do: %{post_message: :native, multi_file: :native, edit_message: :native, edit_attachments: :native}

    def send_message(_, _, _), do: raise("unexpected send_message")

    def post_message(room, _, _) do
      {:ok,
       Response.new(%{
         external_message_id: "post",
         external_room_id: room,
         channel_type: :test,
         metadata: %{attachments: [%{url: "test://file/a", filename: "a.txt"}]}
       })}
    end

    def edit_message(room, id, text, opts) do
      transport = Jido.Chat.Wire.decode_module(opts[:transport])
      transport.edit(room, id, text, opts)
    end
  end

  test "capability matrix is coherent" do
    assert :ok = Jido.Chat.Adapter.validate_capabilities(Adapter)
  end

  for owner <- [Thread, ChannelRef] do
    @owner owner
    test "#{owner} can edit a handle after JSON persistence without discarding defaults" do
      target =
        @owner.new(%{id: "room", adapter: Adapter, adapter_name: :test, external_room_id: "room", external_id: "room"})

      defaults = [
        transport: Transport,
        max_file_size: 1024,
        label: "verbose",
        metadata: %{"custom" => "value", "coordinates" => [1, 2]}
      ]

      payload = Postable.text("original", files: [%{data: "a", filename: "a.txt"}])
      assert {:ok, sent} = @owner.post(target, payload, defaults)
      restored = sent |> SentMessage.to_map() |> Jason.encode!() |> Jason.decode!() |> SentMessage.from_map()
      assert restored.default_opts == Keyword.put(sent.default_opts, :transport, Atom.to_string(Transport))
      assert restored.response.status == :sent
      assert restored.response.channel_type == :test
      assert [attachment] = restored.attachments
      assert attachment.url == "test://file/a"
      assert {:ok, edited} = SentMessage.edit(restored, "changed", max_file_size: 2048)
      assert_received {:edited, "room", "post", "changed", opts}
      assert opts[:max_file_size] == 2048
      assert opts[:transport] == Atom.to_string(Transport)
      assert opts[:label] == "verbose"
      assert opts[:metadata] == %{"custom" => "value", "coordinates" => [1, 2]}
      assert opts[:previous_metadata]["attachments"] == [%{"url" => "test://file/a", "filename" => "a.txt"}]
      assert edited.response.status == :edited
      assert edited.id == "post"

      assert edited
             |> SentMessage.to_map()
             |> Jason.encode!()
             |> Jason.decode!()
             |> SentMessage.from_map()
             |> Map.fetch!(:response)
             |> Map.fetch!(:status) == :edited
    end
  end

  test "list-of-pairs defaults remain usable after map and JSON restoration" do
    sent =
      SentMessage.new(%{
        adapter: Adapter,
        response: %{external_message_id: "post", external_room_id: "room", channel_type: :test}
      })

    for opts <- [
          [["transport", Atom.to_string(Transport)], ["max_file_size", 1024]],
          [[:transport, Transport], [:max_file_size, 1024]],
          [transport: Transport, max_file_size: 1024]
        ] do
      restored = sent |> SentMessage.to_map() |> Map.put("default_opts", opts) |> SentMessage.from_map()

      expected_transport =
        case hd(opts) do
          ["transport", value] -> value
          _ -> Transport
        end

      assert restored.default_opts == [transport: expected_transport, max_file_size: 1024]
      assert {:ok, _} = SentMessage.edit(restored, "legacy", max_file_size: 2048)
      assert_received {:edited, "room", "post", "legacy", forwarded}
      assert forwarded[:max_file_size] == 2048
      assert forwarded[:transport] == expected_transport
    end
  end

  test "response strings normalize without accepting invalid statuses or creating atoms" do
    for status <- [:sent, :edited, :accepted, :failed] do
      response = Response.new(%{"status" => Atom.to_string(status), "channel_type" => "test"})
      assert response.status == status
      assert response.channel_type == :test
    end

    unknown = "unknown_response_#{System.unique_integer([:positive])}"
    assert_raise Jido.Chat.Errors.Validation, fn -> Response.new(%{status: unknown}) end
    assert_raise Jido.Chat.Errors.Validation, fn -> Response.new(%{channel_type: unknown}) end
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
  end

  test "malformed or unknown serialized options cannot create atoms" do
    sent = SentMessage.new(%{adapter: Adapter, response: %{external_message_id: "post"}})
    unknown = "unknown_option_#{System.unique_integer([:positive])}"

    for options <- [
          [[unknown, "value"]],
          [[42, "value"]],
          ["invalid"],
          %{"invalid" => "options"}
        ] do
      assert_raise ArgumentError, fn ->
        sent |> SentMessage.to_map() |> Map.put("default_opts", options) |> SentMessage.from_map()
      end
    end

    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
  end

  test "serialization keeps the existing format without guessing nested option types" do
    sent =
      SentMessage.new(%{
        adapter: Adapter,
        response: %{external_message_id: "post"},
        default_opts: [metadata: %{"mode" => :verbose, "coordinates" => {1, 2}}]
      })

    serialized = SentMessage.to_map(sent)
    assert [[:metadata, %{"mode" => :verbose, "coordinates" => [1, 2]}]] = serialized["default_opts"]

    restored = serialized |> Jason.encode!() |> Jason.decode!() |> SentMessage.from_map()
    assert restored.default_opts == [metadata: %{"mode" => "verbose", "coordinates" => [1, 2]}]
  end
end
