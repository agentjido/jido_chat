manifest_path = Path.expand("../docs/migration/api-map.json")
api = manifest_path |> File.read!() |> Jason.decode!()
version = "../docs/migration/version-matrix.json" |> File.read!() |> Jason.decode!()
entries = api["exports"]

common_generated = [
  child_spec: 1,
  code_change: 3,
  format_status: 1,
  format_status: 2,
  handle_call: 3,
  handle_cast: 2,
  handle_info: 2,
  terminate: 2
]

missing =
  version["packages"]
  |> Enum.filter(&Map.has_key?(&1, "base_sha"))
  |> Enum.flat_map(fn row ->
    app = String.to_existing_atom(row["package"])
    modules = Application.spec(app, :modules) || []

    Enum.flat_map(modules, fn module ->
      Code.ensure_loaded!(module)
      name = module |> Atom.to_string() |> String.trim_leading("Elixir.")
      attrs = module.module_info(:attributes)
      behaviours = Keyword.get_values(attrs, :behaviour) |> List.flatten()

      actual = module.__info__(:functions) ++ module.__info__(:macros)

      known =
        entries
        |> Enum.filter(&(&1["module"] == name))
        |> Enum.map(&{&1["function"], &1["arity"]})

      template =
        if Jido.Messaging in behaviours or function_exported?(module, :__jido_messaging__, 1),
          do: "Jido.Messaging",
          else: nil

      template_known =
        entries
        |> Enum.filter(&(&1["module"] == template and &1["generated_template"]))
        |> Enum.map(&{&1["function"], &1["arity"]})

      actual
      |> Enum.flat_map(fn {function, arity} ->
        key = {Atom.to_string(function), arity}

        generated =
          function in [:__struct__, :__info__, :module_info] or
            ({function, arity} in common_generated and
               Enum.any?(behaviours, &(&1 in [GenServer, Supervisor, DynamicSupervisor]))) or
            (function == :channel_type and Jido.Chat.Adapter in behaviours)

        new_identity =
          name in [
            "Jido.Chat.Signal.Identity",
            "Jido.Messaging.Signal.Identity",
            "Jido.Messaging.Signal.Context"
          ]

        if generated or new_identity or key in known or key in template_known do
          []
        else
          [%{package: row["package"], module: name, function: function, arity: arity}]
        end
      end)
    end)
  end)

result = %{
  state: if(missing == [], do: "pass", else: "fail"),
  missing: missing,
  source_entries: length(entries)
}

File.write!(
  "../docs/migration/evidence/g1/api-export-audit.json",
  Jason.encode!(result, pretty: true) <> "\n"
)

IO.puts(Jason.encode!(result, pretty: true))
if missing != [], do: System.halt(1)
