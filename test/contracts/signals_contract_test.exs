defmodule Jido.Chat.SignalsContractTest do
  use Covenant.Case, component: "jido_chat.signals", async: true
  alias Jido.Chat
  alias Jido.Chat.ContractFixtures, as: F

  @tag obligation: "jido_chat.signals.I1"
  test "the complete core catalog preserves its literal identities and data schemas" do
    expected = F.entries()

    assert Enum.frequencies_by(expected, & &1["kind"]) == %{
             "command" => 13,
             "query" => 10,
             "result" => 46,
             "fact" => 17
           }

    assert Enum.sort(Enum.map(Chat.signal_definitions(), &inspect/1)) == Enum.sort(Enum.map(expected, & &1["module"]))

    assert Enum.sort(Enum.map(Chat.event_definitions(), &inspect/1)) ==
             expected |> Enum.filter(&(&1["kind"] == "fact")) |> Enum.map(& &1["module"]) |> Enum.sort()

    assert length(Enum.uniq_by(expected, & &1["type"])) == 86
    assert length(Enum.uniq_by(expected, & &1["dataschema"])) == 86

    for entry <- expected do
      definition = F.module(entry["module"])
      assert definition.type() == entry["type"]
      assert definition.dataschema() == entry["dataschema"]
      actual_schema = definition.schema() |> Zoi.to_json_schema() |> Jason.encode!() |> Jason.decode!()
      assert actual_schema == entry["data_schema"], "data schema changed for #{entry["module"]}"
      assert {:ok, signal} = definition.new(entry["fixture"], entry["fixture_options"])
      assert signal.type == entry["type"]
      assert signal.dataschema == entry["dataschema"]
    end
  end

  @tag obligation: "jido_chat.signals.I2"
  test "all definitions reject missing required data, unknown fields, and invalid values" do
    for entry <- F.entries() do
      definition = F.module(entry["module"])
      data = entry["fixture"]
      opts = entry["fixture_options"]
      assert {:error, %Chat.Errors.Contract{}} = definition.new(Map.put(data, "unapproved_field", true), opts)
      assert {:error, %Chat.Errors.Contract{}} = definition.new(nil, opts)

      for key <- entry["data_schema"]["required"] do
        assert {:error, %Chat.Errors.Contract{}} = definition.new(Map.delete(data, key), opts)
      end

      for key <- Map.keys(data) do
        assert {:error, %Chat.Errors.Contract{}} = definition.new(Map.put(data, key, self()), opts)
      end
    end

    request = F.entry(Chat.Signal.SendMessage)["fixture"]

    for opts <- [
          [type: "override"],
          [dataschema: "urn:override"],
          [data: %{}],
          [source: "urn:first", source: "urn:second"]
        ] do
      assert {:error, %Chat.Errors.Contract{}} = Chat.Signal.SendMessage.new(request, opts)
    end
  end

  @tag obligation: "jido_chat.signals.I3"
  test "nested private data and invalid runtime context cannot enter Signals" do
    client = F.client()
    base = F.message(client)
    ref = %{"client_id" => client.id, "kind" => "media", "id" => "file-1"}
    media = %{"kind" => "file", "resource_ref" => ref, "metadata" => %{"nested" => %{"safe" => "value"}}}
    assert {:ok, _} = Chat.Signal.MessageReceived.new(Map.put(base.data, "media", [media]))

    values =
      [self(), fn -> :runtime end, %URI{host: "example.com"}, <<255>>] ++
        Enum.map(
          ~w(raw credentials token access_token refresh_token password secret client pid qr pairing_code),
          &%{&1 => "private-token"}
        )

    for value <- values do
      bad_media = put_in(media, ["metadata", "nested"], value)

      assert {:error, %Chat.Errors.Contract{}} =
               Chat.Signal.MessageReceived.new(Map.put(base.data, "media", [bad_media]))
    end

    request = F.entry(Chat.Signal.SendMessage)["fixture"]

    for opts <- [
          [extensions: %{"unapproved" => "value"}],
          [extensions: %{"traceparent" => "invalid"}],
          [extensions: %{"tracestate" => "missing=parent"}],
          [extensions: %{"causationid" => String.duplicate("x", 129)}],
          [source: "https://user:private-token@example.com"],
          [id: String.duplicate("x", 129)],
          [id: ""],
          [id: <<255>>]
        ] do
      assert {:error, %Chat.Errors.Contract{}} = Chat.Signal.SendMessage.new(request, opts)
    end

    assert {:ok, _} =
             Chat.Signal.SendMessage.new(request,
               id: String.duplicate("x", 128),
               extensions: %{"traceparent" => F.trace(), "tracestate" => "contract=ok", "causationid" => "parent"}
             )
  end

  @tag obligation: "jido_chat.signals.I4"
  test "all native Signal examples retain identity and trace through Catalog serialization" do
    for entry <- F.entries() do
      definition = F.module(entry["module"])
      assert {:ok, signal} = definition.new(entry["fixture"], entry["fixture_options"])
      assert %Jido.Signal.Trace{} = Jido.Signal.Trace.get(signal)
      assert F.round_trip(signal) == signal
      wire = Jido.Signal.to_map(signal)
      assert {:error, _} = Jido.Signal.Catalog.decode(Chat.catalog(), Map.put(wire, "type", "unknown.chat.type"))
      assert {:error, _} = Jido.Signal.Catalog.decode(Chat.catalog(), Map.put(wire, "dataschema", "urn:unknown:1"))
    end
  end

  @tag obligation: "jido_chat.signals.I5"
  test "file sources and download results use one portable JSON contract" do
    client = F.client()
    data = %{"client_id" => client.id, "request_id" => "file", "room_id" => "room/1"}
    sources = for kind <- ["file", "url", "media"], do: %{"client_id" => client.id, "kind" => kind, "id" => "reference"}
    sources = sources ++ [%{"content_base64" => Base.encode64(<<0, 255, 1>>), "filename" => "bytes.bin"}]

    for source <- sources do
      assert {:ok, signal} = Chat.Signal.SendFile.new(Map.put(data, "source", source))
      assert signal.data["source"] == source
      assert F.round_trip(signal) == signal
    end

    for source <- [
          %{},
          %{"content_base64" => "", "filename" => "empty"},
          %{"content_base64" => "bad", "filename" => "file"},
          %{"content_base64" => "YQ=="},
          %{"client_id" => client.id, "kind" => "invalid", "id" => "f"}
        ] do
      assert {:error, %Chat.Errors.Contract{}} = Chat.Signal.SendFile.new(Map.put(data, "source", source))
    end

    for bytes <- ["", <<0, 255, 1>>] do
      result = %{"content_base64" => Base.encode64(bytes)}

      envelope = %{
        "client_id" => client.id,
        "request_id" => "download",
        "operation" => "jido.chat.query.download_file",
        "result" => result
      }

      assert {:ok, downloaded} = Chat.DownloadFile.Completed.new(envelope)
      assert Base.decode64!(downloaded.data["result"]["content_base64"]) == bytes

      assert {:error, %Chat.Errors.Contract{}} =
               Chat.DownloadFile.Completed.new(put_in(envelope, ["result", "content_base64"], "invalid"))
    end
  end

  @tag obligation: "jido_chat.signals.I5"
  test "keyboards enforce callback byte, row, and total button limits" do
    data = F.entry(Chat.Signal.SendMessage)["fixture"]
    button = %{"text" => "Confirm", "value" => String.duplicate("é", 32)}
    row = List.duplicate(button, 8)
    maximum = %{"rows" => List.duplicate(row, 12) ++ [List.duplicate(button, 4)]}
    assert {:ok, signal} = Chat.Signal.SendMessage.new(Map.put(data, "keyboard", maximum))
    assert F.round_trip(signal) == signal

    assert {:ok, _} =
             Chat.Signal.SendMessage.new(
               Map.put(data, "keyboard", %{"rows" => [[%{"text" => "Help", "url" => "https://example.com"}]]})
             )

    edit = F.entry(Chat.Signal.EditMessage)["fixture"] |> Map.put("keyboard", %{"rows" => []})
    assert {:ok, _} = Chat.Signal.EditMessage.new(edit)

    invalid = [
      %{"rows" => [[%{"text" => "No target"}]]},
      %{"rows" => [[Map.put(button, "url", "https://example.com")]]},
      %{"rows" => [[Map.put(button, "value", String.duplicate("é", 33))]]},
      %{"rows" => [List.duplicate(button, 9)]},
      %{"rows" => List.duplicate(row, 12) ++ [List.duplicate(button, 5)]},
      %{"rows" => [[]]}
    ]

    for keyboard <- invalid,
        do: assert({:error, %Chat.Errors.Contract{}} = Chat.Signal.SendMessage.new(Map.put(data, "keyboard", keyboard)))
  end

  @tag obligation: "jido_chat.signals.I6"
  test "a Signal accepts the exact encoded byte limit and rejects one extra byte" do
    data = %{"client_id" => "alpha", "request_id" => "size", "room_id" => "room/1", "text" => ""}
    opts = [id: "fixed-size", time: "2026-10-17T12:00:00Z", extensions: %{"traceparent" => F.trace()}]
    assert {:ok, base} = Chat.Signal.SendMessage.new(data, opts)
    assert {:ok, encoded} = Jido.Signal.Serialization.serialize(base)
    fill = 262_144 - byte_size(encoded)
    assert {:ok, maximum} = Chat.Signal.SendMessage.new(%{data | "text" => String.duplicate("x", fill)}, opts)
    assert {:ok, encoded} = Jido.Signal.Serialization.serialize(maximum)
    assert byte_size(encoded) == 262_144

    assert {:error, %Chat.Errors.Contract{code: :signal_too_large}} =
             Chat.Signal.SendMessage.new(%{data | "text" => String.duplicate("x", fill + 1)}, opts)
  end

  @tag obligation: "jido_chat.signals.I6"
  test "Deliveries enforce count, failure, and encoded byte limits as a complete ordered batch" do
    client = F.client()
    fact = F.message(client)
    assert {:ok, maximum} = Chat.Delivery.new(client, "delivery-1", List.duplicate(fact, 100))
    assert length(maximum.signals) == 100

    assert {:error, %Chat.Errors.Contract{code: :too_many_signals}} =
             Chat.Delivery.new(client, "delivery-1", List.duplicate(fact, 101))

    failure =
      Chat.Signal.NormalizationFailed.new!(
        %{"item_id" => "failed", "delivery_id" => "delivery-1", "code" => "invalid_item", "item_index" => 0},
        source: client.source
      )

    assert {:ok, _} = Chat.Delivery.new(client, "delivery-1", List.duplicate(failure, 20))

    assert {:error, %Chat.Errors.Contract{code: :too_many_failures}} =
             Chat.Delivery.new(client, "delivery-1", List.duplicate(failure, 21))

    fixed = [
      id: "fixed-fact",
      time: "2026-10-17T12:00:00Z",
      source: client.source,
      subject: fact.subject,
      extensions: %{"traceparent" => F.trace()}
    ]

    empty = Chat.Signal.MessageReceived.new!(%{fact.data | "text" => ""}, fixed)

    base_size =
      byte_size(
        Jason.encode!(%{"id" => "delivery-1", "signals" => Enum.map(List.duplicate(empty, 5), &Jido.Signal.to_map/1)})
      )

    fill = 1_048_576 - base_size
    lengths = [div(fill, 5), div(fill, 5), div(fill, 5), div(fill, 5), div(fill, 5) + rem(fill, 5)]

    signals =
      Enum.map(lengths, fn size ->
        Chat.Signal.MessageReceived.new!(%{fact.data | "text" => String.duplicate("x", size)}, fixed)
      end)

    assert byte_size(Jason.encode!(%{"id" => "delivery-1", "signals" => Enum.map(signals, &Jido.Signal.to_map/1)})) ==
             1_048_576

    assert {:ok, delivery} = Chat.Delivery.new(client, "delivery-1", signals)
    assert delivery.signals == signals
    [first | rest] = signals
    larger = %{first | data: Map.update!(first.data, "text", &(&1 <> "x"))}

    assert {:error, %Chat.Errors.Contract{code: :delivery_too_large}} =
             Chat.Delivery.new(client, "delivery-1", [larger | rest])
  end
end
