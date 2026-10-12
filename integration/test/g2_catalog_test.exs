defmodule Jido.Chat.Integration.NativeCatalogTest do
  use ExUnit.Case, async: true

  alias Jido.Signal.{Catalog, Serialization}

  @entries "../docs/migration/catalog.json"
           |> File.read!()
           |> Jason.decode!()
           |> Map.fetch!("definitions")

  for entry <- @entries do
    test "public native catalog fixture #{entry["module"]}" do
      entry = unquote(Macro.escape(entry))
      module = Module.concat([entry["module"]])
      assert {:ok, signal} = module.new(entry["fixture"], entry["fixture_options"])

      catalog =
        Catalog.new!(Jido.Chat.signal_definitions() ++ Jido.Messaging.signal_definitions())

      assert signal.type == entry["type"]
      assert signal.dataschema == entry["dataschema"]
      assert signal.data == entry["fixture"]
      assert {:ok, ^signal} = Catalog.validate(catalog, signal)
      assert {:ok, json} = Serialization.serialize(signal)
      assert {:ok, ^signal} = Catalog.decode(catalog, json)
    end
  end

  test "core and the Signal provider keep one parent module and exact domain ownership" do
    assert Code.ensure_loaded?(Jido.Chat.Signal)

    assert Jido.Chat.Signal.module_info(:compile)[:source]
           |> to_string()
           |> String.contains?("jido_chat_signal")

    for module <- Jido.Chat.signal_definitions() do
      assert module.__signal_owner__() == :chat
      assert String.starts_with?(module.type(), "jido.chat.")
    end

    for module <- Jido.Messaging.signal_definitions() do
      assert module.__signal_owner__() == :messaging
      assert String.starts_with?(module.type(), "jido.messaging.")
    end
  end
end
