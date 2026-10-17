defmodule Jido.Chat.PublicSignalContractTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Errors.Contract
  alias Jido.Signal.{Catalog, Serialization}

  @catalog_file Path.expand("../../../docs/migration/catalog.json", __DIR__)
  @entries @catalog_file
           |> File.read!()
           |> Jason.decode!()
           |> Map.fetch!("definitions")
           |> Enum.filter(&(&1["owner"] == "chat"))

  for entry <- @entries do
    test "native definition #{entry["module"]} keeps identity through JSON and Catalog" do
      entry = unquote(Macro.escape(entry))
      module = Module.concat([entry["module"]])
      assert {:ok, signal} = module.new(entry["fixture"], entry["fixture_options"])
      assert signal.type == entry["type"]
      assert signal.dataschema == entry["dataschema"]
      assert %Jido.Signal.Trace{} = Jido.Signal.Trace.get(signal)
      catalog = Catalog.new!(Jido.Chat.signal_definitions())
      assert {:ok, ^signal} = Catalog.validate(catalog, signal)
      assert {:ok, wire} = Serialization.serialize(signal)
      assert {:ok, ^signal} = Catalog.decode(catalog, wire)
    end
  end

  test "constructor metadata override attempts fail with one structured contract error" do
    data = %{"request_id" => "request-1", "room_id" => "room-1", "text" => "hello"}

    for opts <- [
          [type: "evil.override"],
          [dataschema: "urn:evil:schema:1"],
          [data: %{}],
          [source: "/one", source: "/two"]
        ] do
      assert {:error, %Contract{code: :invalid_options}} = Jido.Chat.Signal.SendMessage.new(data, opts)
    end
  end

  test "private values and unapproved context fail without a raw fallback" do
    data = %{"request_id" => "request-1", "room_id" => "room-1", "text" => "hello"}

    for value <- [self(), fn -> :private end, <<255>>, %{token: "private"}] do
      assert {:error, %Contract{}} = Jido.Chat.Signal.SendMessage.new(%{data | "text" => value})
    end

    assert {:error, %Contract{code: :invalid_context}} =
             Jido.Chat.Signal.SendMessage.new(data, extensions: %{"correlationid" => "legacy"})

    assert {:error, %Contract{code: :invalid_context}} =
             Jido.Chat.Signal.SendMessage.new(data, extensions: %{"traceparent" => "invalid"})
  end

  test "encoded Signal size is accepted at the exact limit and rejected one byte beyond" do
    data = %{"request_id" => "request-1", "room_id" => "room-1", "text" => ""}
    opts = [id: "fixture-size", time: "2026-10-12T12:00:00Z"]
    assert {:ok, base} = Jido.Chat.Signal.SendMessage.new(data, opts)
    assert {:ok, encoded} = Serialization.serialize(base)
    fill = 262_144 - byte_size(encoded)
    assert {:ok, signal} = Jido.Chat.Signal.SendMessage.new(%{data | "text" => String.duplicate("x", fill)}, opts)
    assert {:ok, encoded} = Serialization.serialize(signal)
    assert byte_size(encoded) == 262_144

    assert {:error, %Contract{code: :signal_too_large}} =
             Jido.Chat.Signal.SendMessage.new(%{data | "text" => String.duplicate("x", fill + 1)}, opts)
  end
end
