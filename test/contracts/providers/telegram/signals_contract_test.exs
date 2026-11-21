defmodule Jido.Chat.Telegram.SignalsContractTest do
  use Covenant.Case, component: "jido_chat_telegram.signals", async: true
  alias Jido.Chat
  alias Jido.Chat.Telegram
  alias Jido.Chat.Telegram.ContractFixtures, as: F

  @tag obligation: "jido_chat_telegram.signals.I1"
  test "all forty-two definition identities and JSON data schemas match the fixed manifest" do
    entries = F.entries()
    assert Enum.frequencies_by(entries, & &1["kind"]) == %{"command" => 10, "query" => 4, "result" => 28}
    assert length(Enum.uniq_by(entries, & &1["type"])) == 42
    assert length(Enum.uniq_by(entries, & &1["dataschema"])) == 42

    assert Enum.sort(Enum.map(Telegram.signal_definitions(), &inspect/1)) ==
             Enum.sort(Enum.map(entries, & &1["module"]))

    for entry <- entries do
      definition = F.module(entry["module"])
      assert definition.type() == entry["type"]
      assert definition.dataschema() == entry["dataschema"]
      schema = definition.schema() |> Zoi.to_json_schema() |> Jason.encode!() |> Jason.decode!()
      assert schema == entry["data_schema"], "Signal schema changed: #{entry["module"]}"
      assert {:ok, signal} = definition.new(entry["fixture"], entry["fixture_options"])
      assert signal.type == entry["type"]
      assert signal.dataschema == entry["dataschema"]
    end

    for row <- F.cases() do
      action = F.module(row["action"])

      assert action.signal_definitions() == [
               action.signal_definition(),
               Module.concat(action, Completed),
               Module.concat(action, Failed)
             ]

      assert {action.signal_definition(), action} in Telegram.operations()
    end
  end

  @tag obligation: "jido_chat_telegram.signals.I2"
  test "every typed constructor rejects missing required fields, unknown fields, and runtime values" do
    for entry <- F.entries() do
      definition = F.module(entry["module"])
      data = entry["fixture"]
      opts = entry["fixture_options"]
      assert {:error, _} = definition.new(nil, opts)
      assert {:error, _} = definition.new(Map.put(data, "unapproved_field", true), opts)

      for key <- entry["data_schema"]["required"],
          do: assert({:error, _} = definition.new(Map.delete(data, key), opts))

      for key <- Map.keys(data),
          do: assert({:error, _} = definition.new(Map.put(data, key, self()), opts))

      if String.ends_with?(entry["type"], ".completed") or String.ends_with?(entry["type"], ".failed"),
        do: assert({:error, _} = definition.new(Map.put(data, "operation", "jido.chat.telegram.command.unknown"), opts))

      if String.ends_with?(entry["type"], ".failed") do
        for change <- [%{"code" => "raw_provider_error"}, %{"outcome" => "safe_to_retry"}, %{"retry_after_ms" => -1}] do
          assert {:error, _} = definition.new(Map.merge(data, change), opts)
        end
      end
    end
  end

  @tag obligation: "jido_chat_telegram.signals.I3"
  test "every definition round trips with causal context through provider and configured catalogs" do
    client = F.client()
    catalogs = [Telegram.catalog(), Chat.catalog(client)]

    for entry <- F.entries() do
      definition = F.module(entry["module"])
      assert {:ok, signal} = definition.new(entry["fixture"], entry["fixture_options"])
      assert signal.extensions["traceparent"] == F.trace()
      assert signal.extensions["tracestate"] == "contract=telegram"
      assert signal.extensions["jidocausationid"] == "fixture-parent"

      for catalog <- catalogs do
        assert F.round_trip(signal, catalog) == signal
        wire = Jido.Signal.Codec.to_map(signal)
        assert {:error, _} = Jido.Signal.Catalog.decode(catalog, Map.put(wire, "type", "jido.chat.telegram.unknown"))
        assert {:error, _} = Jido.Signal.Catalog.decode(catalog, Map.put(wire, "dataschema", "urn:unknown:1"))
      end

      refute definition in Chat.signal_definitions()
      assert {:error, _} = Jido.Signal.Catalog.validate(Chat.catalog(), signal)
    end

    assert length(Chat.signal_definitions()) == 86
    refute_receive {:telegram_contract_wire, _, _, _, _, _}
  end

  @tag obligation: "jido_chat_telegram.signals.I4"
  test "the Action boundary rejects private context and produces only canonical public results" do
    client = F.client()

    for row <- F.cases() do
      action = F.module(row["action"])
      request = F.request(action, client)

      for bad <- [
            %{request | source: "https://user:fixture-token:alpha@example.com/source"},
            %{request | extensions: %{"traceparent" => "invalid"}},
            %{request | extensions: Map.put(request.extensions, "privatetoken", "never-project-this")},
            %{request | data: Map.put(request.data, "raw", %{"credentials" => "never-project-this"})}
          ] do
        assert {:error, _} = Jido.Chat.Telegram.ActionHelpers.execute(action, bad, %{client: client}, max_attempts: 1)

        assert {:error, _} =
                 Jido.Exec.run(action, %{"signal" => Jido.Signal.Codec.to_map(bad)}, %{client: client}, max_attempts: 1)
      end
    end

    refute_receive {:telegram_contract_wire, _, _, _, _, _}
    raw = %{"id" => 99, "is_bot" => false, "token" => "never-project-this", "raw" => %{secret: self()}}

    assert {:ok, %{signal: completed}} =
             F.run(Telegram.GetMe, client, %{}, contract_response: {:ok, raw}, local_setting: "never-project-this")

    assert completed.data["result"] == %{"id" => "99", "is_bot" => false}
    assert completed.source == client.source
    assert F.round_trip(completed) == completed
    assert_receive {:telegram_contract_wire, _, "getMe", %{}, _, _}
    refute_receive {:telegram_contract_wire, _, _, _, _, _}
  end

  @tag obligation: "jido_chat_telegram.signals.I5"
  test "poll, draft, callback, fetch, and webhook constraints preserve valid false and zero values" do
    client = F.client()

    for {action, invalid} <- [
          {Telegram.SendPoll,
           [
             %{"question" => ""},
             %{"question" => String.duplicate("x", 301)},
             %{"options" => ["one"]},
             %{"options" => List.duplicate("one", 13)},
             %{"options" => ["", "two"]},
             %{"options" => [String.duplicate("x", 101), "two"]}
           ]},
          {Telegram.SendDraft,
           [
             %{"room_id" => "@channel"},
             %{"room_id" => "123suffix"},
             %{"draft_id" => 0},
             %{"text" => ""},
             %{"format" => "unsupported"}
           ]},
          {Telegram.AnswerCallbackQuery, [%{"text" => String.duplicate("x", 201)}, %{"show_alert" => "false"}]},
          {Telegram.FetchUpdates,
           [
             %{"offset" => -1},
             %{"limit" => 0},
             %{"limit" => 101},
             %{"timeout" => -1},
             %{"timeout" => 51},
             %{"allowed_updates" => [""]}
           ]},
          {Telegram.SetWebhook,
           [
             %{"url" => ""},
             %{"max_connections" => 0},
             %{"max_connections" => 101},
             %{"secret_token" => "never-project-this"}
           ]}
        ] do
      data = F.request(action, client).data
      for change <- invalid, do: assert({:error, _} = action.signal_definition().new(Map.merge(data, change)))
    end

    for {action, fields} <- [
          {Telegram.SendPoll,
           %{
             "question" => String.duplicate("x", 300),
             "options" => List.duplicate(String.duplicate("x", 100), 12),
             "is_anonymous" => false
           }},
          {Telegram.SendDraft, %{"room_id" => "-100123", "draft_id" => 1}},
          {Telegram.AnswerCallbackQuery, %{"text" => String.duplicate("x", 200), "show_alert" => false}},
          {Telegram.FetchUpdates, %{"offset" => 0, "limit" => 100, "timeout" => 50, "allowed_updates" => []}},
          {Telegram.SetWebhook, %{"max_connections" => 100, "drop_pending_updates" => false}}
        ] do
      assert %Jido.Signal{} = F.request(action, client, fields)
    end

    refute_receive {:telegram_contract_wire, _, _, _, _, _}
  end

  @tag obligation: "jido_chat_telegram.signals.I5"
  test "media, keyboards, and file metadata keep the shared portable constraints" do
    client = F.client()
    data = F.request(Telegram.SendDocument, client).data

    for source <- [
          %{"client_id" => client.id, "kind" => "media", "id" => "telegram://file/file-1"},
          %{"client_id" => client.id, "kind" => "file", "id" => "/tmp/report.txt"},
          %{"client_id" => client.id, "kind" => "url", "id" => "https://example.com/report.txt"},
          %{"content_base64" => Base.encode64(<<0, 255>>), "filename" => "report.bin"}
        ] do
      assert {:ok, _} = Telegram.Signal.SendDocument.new(Map.put(data, "source", source))
    end

    for source <- [%{}, %{"content_base64" => "invalid", "filename" => "report.bin"}, %{"content_base64" => "YQ=="}] do
      assert {:error, _} = Telegram.Signal.SendDocument.new(Map.put(data, "source", source))
    end

    for action <- [Telegram.SendSticker, Telegram.SendVideoNote] do
      assert {:error, _} =
               action.signal_definition().new(F.request(action, client).data |> Map.put("caption", "unsupported"))
    end

    button = %{"text" => "Confirm", "value" => String.duplicate("é", 32)}
    assert {:ok, _} = Telegram.Signal.SendDocument.new(Map.put(data, "keyboard", %{"rows" => [[button]]}))

    for keyboard <- [
          %{"rows" => [[Map.put(button, "value", String.duplicate("é", 33))]]},
          %{"rows" => [[Map.put(button, "url", "https://example.com")]]},
          %{"rows" => [List.duplicate(button, 9)]},
          %{"rows" => List.duplicate(List.duplicate(button, 8), 12) ++ [List.duplicate(button, 5)]}
        ] do
      assert {:error, _} = Telegram.Signal.SendDocument.new(Map.put(data, "keyboard", keyboard))
    end

    entry = F.entry(Telegram.GetFile.Completed)
    result = entry["fixture"]

    for path <- ["documents/report.txt", "photos/a-b_1.jpg"] do
      assert {:ok, _} = Telegram.GetFile.Completed.new(put_in(result, ["result", "file_path"], path))
    end

    for path <- ["../secret", "/absolute", "a//b", "a/./b", "a/../b", "a?token=secret"] do
      assert {:error, _} = Telegram.GetFile.Completed.new(put_in(result, ["result", "file_path"], path))
    end

    assert {:error, _} = Telegram.GetFile.Completed.new(put_in(result, ["result", "size"], -1))
    assert {:ok, _} = Telegram.GetFile.Completed.new(put_in(result, ["result", "size"], 0))
    refute_receive {:telegram_contract_wire, _, _, _, _, _}
  end

  @tag obligation: "jido_chat_telegram.signals.I6"
  test "the Action accepts the exact Signal byte limit and rejects one additional byte before I/O" do
    client = F.client()
    request = F.request(Telegram.SendDraft, client, %{"text" => "x"})
    request = %{request | id: "fixed-size", time: "2026-10-18T12:00:00Z"}
    assert {:ok, json} = Jido.Signal.Codec.serialize(request)
    fill = 262_144 - byte_size(json) + 1
    maximum = %{request | data: Map.put(request.data, "text", String.duplicate("x", fill))}
    assert {:ok, json} = Jido.Signal.Codec.serialize(maximum)
    assert byte_size(json) == 262_144

    assert {:ok, %{signal: completed}} =
             Jido.Chat.Telegram.ActionHelpers.execute(Telegram.SendDraft, maximum, %{client: client}, max_attempts: 1)

    assert completed.data["result"]["acknowledged"]
    assert_receive {:telegram_contract_wire, _, "sendMessageDraft", _, _, _}
    larger = %{maximum | data: Map.update!(maximum.data, "text", &(&1 <> "x"))}

    assert {:error, _} =
             Jido.Chat.Telegram.ActionHelpers.execute(Telegram.SendDraft, larger, %{client: client}, max_attempts: 1)

    refute_receive {:telegram_contract_wire, _, _, _, _, _}
  end

  @tag obligation: "jido_chat_telegram.signals.I6"
  test "incoming count, failure, Signal size, and Delivery size limits reject the complete batch" do
    client = F.client()
    update = hd(F.incoming())["update"]
    assert {:ok, maximum} = Chat.normalize(client, Enum.map(1..100, &Map.put(update, "update_id", &1)))
    assert length(maximum.signals) == 100
    failures = Enum.map(1..20, &%{"update_id" => &1, "message" => %{}})
    assert {:ok, maximum} = Chat.normalize(client, failures)
    assert length(maximum.signals) == 20

    for {input, code} <- [
          {Enum.map(1..101, &Map.put(update, "update_id", &1)), :too_many_signals},
          {failures ++ [%{"update_id" => 21, "message" => %{}}], :too_many_failures},
          {put_in(update, ["message", "text"], String.duplicate("x", 262_144)), :signal_too_large},
          {Enum.map(1..6, fn id ->
             update |> Map.put("update_id", id) |> put_in(["message", "text"], String.duplicate("x", 200_000))
           end), :delivery_too_large}
        ] do
      assert {:error, %Chat.Errors.Contract{code: ^code}} = Chat.normalize(client, input)
    end

    refute_receive {:telegram_contract_wire, _, _, _, _, _}
  end
end
