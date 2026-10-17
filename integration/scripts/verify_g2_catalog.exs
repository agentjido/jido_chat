# G2 checks definition sources only. G3/G7 still require the full Messaging application.
gate = List.first(System.argv()) || "G2"
true = gate in ["G2", "G3", "G7"]
core = Path.expand("../..", __DIR__)
messaging = Path.join(Path.dirname(core), "jido_messaging")

source =
  messaging |> Path.join("lib/jido_messaging.ex") |> File.read!() |> Code.string_to_quoted!()

{_ast, bodies} =
  Macro.prewalk(source, [], fn
    {:def, _, [{:signal_definitions, _, _}, [do: body]]} = node, rows -> {node, [body | rows]}
    node, rows -> {node, rows}
  end)

[body] = bodies
true = is_list(body)
runtime_definitions = Enum.map(body, fn {:__aliases__, _, parts} -> Module.concat(parts) end)

for module <- runtime_definitions do
  file = module |> Module.split() |> List.last() |> Macro.underscore()
  Code.compile_file(Path.join(messaging, "lib/jido_messaging/signal/#{file}.ex"))
end

Code.compile_file(Path.join(Path.dirname(core), "jido_chat_signal/lib/jido_chat_signal.ex"))
Code.compile_file(Path.join(core, "integration/lib/manifest.ex"))
manifest = Jido.Chat.Integration.Manifest.verify(Path.join(core, "docs/migration"), "G1")
"pass" = manifest.state

entries =
  core
  |> Path.join("docs/migration/catalog.json")
  |> File.read!()
  |> Jason.decode!()
  |> Map.fetch!("definitions")

definitions = Jido.Chat.signal_definitions() ++ runtime_definitions
true = length(definitions) == 110
catalog = Jido.Signal.Catalog.new!(definitions)

rows =
  Enum.map(entries, fn entry ->
    module = Module.concat([entry["module"]])
    {:ok, signal} = module.new(entry["fixture"], entry["fixture_options"])
    true = signal.type == entry["type"] and signal.dataschema == entry["dataschema"]
    true = signal.data == entry["fixture"]
    {:ok, ^signal} = Jido.Signal.Catalog.validate(catalog, signal)
    {:ok, json} = Jido.Signal.Serialization.serialize(signal)
    {:ok, ^signal} = Jido.Signal.Catalog.decode(catalog, json)
    %Jido.Signal.Trace{} = Jido.Signal.Trace.get(signal)
    %{module: entry["module"], state: "pass"}
  end)

true =
  to_string(Jido.Chat.Signal.module_info(:compile)[:source])
  |> String.contains?("jido_chat_signal")

result = %{
  gate: gate,
  state: "pass",
  scope: "typed definitions; full runtime verification remains in G3/G7",
  definition_count: length(rows),
  parent_owner: "jido_chat_signal",
  manifest: manifest,
  definitions: rows
}

File.write!(
  Path.join(
    core,
    "docs/migration/evidence/#{String.downcase(gate)}/#{String.downcase(gate)}-final-catalog-report.json"
  ),
  Jason.encode!(result, pretty: true) <> "\n"
)

IO.puts(Jason.encode!(Map.drop(result, [:definitions]), pretty: true))
