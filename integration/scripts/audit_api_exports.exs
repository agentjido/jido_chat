# Run with mix run after compiling the selected dependency graph.
{opts, _, invalid} =
  OptionParser.parse(System.argv(), strict: [phase: :string, manifest: :string, output: :string])

phase = Keyword.get(opts, :phase, "G7")

if invalid != [] or phase not in ["G3", "G7"],
  do: raise(ArgumentError, "Use --phase G3 or G7 and optional --manifest PATH --output PATH.")

core = Path.expand("../..", __DIR__)

manifest_dir =
  opts
  |> Keyword.get(:manifest, Path.join(core, "docs/migration/version-matrix.json"))
  |> Path.expand()
  |> Path.dirname()

api = manifest_dir |> Path.join("api-map.json") |> File.read!() |> Jason.decode!()
version = manifest_dir |> Path.join("version-matrix.json") |> File.read!() |> Jason.decode!()
catalog = manifest_dir |> Path.join("catalog.json") |> File.read!() |> Jason.decode!()
core_api = manifest_dir |> Path.join("new-major-core-api.json") |> File.read!() |> Jason.decode!()

retired_core =
  manifest_dir |> Path.join("core-retired-modules.json") |> File.read!() |> Jason.decode!()

entries = api["exports"] ++ core_api["exports"]
definitions = Enum.map(catalog["definitions"], & &1["module"])
retired_modules = retired_core["modules"] ++ api["retired_wrapper_modules"]

packages =
  version["packages"]
  |> Enum.filter(&Map.has_key?(&1, "base_sha"))
  |> Enum.filter(&(phase == "G7" or &1["package"] in ["jido_chat", "jido_messaging"]))

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

{exports, failures} =
  Enum.reduce(packages, {[], []}, fn package, {all, failures} ->
    app = String.to_atom(package["package"])

    case Application.spec(app, :modules) do
      modules when is_list(modules) and modules != [] ->
        rows =
          Enum.flat_map(modules, fn module ->
            Code.ensure_loaded!(module)
            source = module.module_info(:compile)[:source] |> to_string()
            name = module |> Atom.to_string() |> String.trim_leading("Elixir.")
            template? = function_exported?(module, :__jido_messaging__, 1)

            if String.contains?(source, "/lib/") or template? do
              behaviours =
                module.module_info(:attributes)
                |> Keyword.get_values(:behaviour)
                |> List.flatten()

              source_ok? =
                String.starts_with?(Path.expand(source), Path.expand(package["worktree"]) <> "/")

              for {function, arity} <- module.__info__(:functions) ++ module.__info__(:macros),
                  function not in [:__struct__, :__info__, :module_info] do
                known =
                  Enum.find(entries, fn entry ->
                    (entry["module"] == name or
                       (template? and entry["module"] == "Jido.Messaging" and
                          entry["generated_template"] == true)) and
                      entry["function"] == Atom.to_string(function) and entry["arity"] == arity and
                      (template? or entry["generated_template"] != true)
                  end)

                generated? =
                  ({function, arity} in common_generated and
                     Enum.any?(behaviours, &(&1 in [GenServer, Supervisor, DynamicSupervisor]))) or
                    (function == :channel_type and Jido.Chat.Adapter in behaviours)

                classification =
                  cond do
                    known ->
                      known["classification"]

                    name in definitions ->
                      if function in [:new, :new!],
                        do: "request-result",
                        else: "private-implementation"

                    generated? ->
                      "private-implementation"

                    true ->
                      "missing"
                  end

                reason =
                  cond do
                    not source_ok? ->
                      "compiled_source_outside_worktree"

                    name in retired_modules or
                        (known && known["implementation_state"] == "retired") ->
                      "retired_export"

                    classification == "missing" ->
                      "unmapped_export"

                    true ->
                      nil
                  end

                %{
                  package: package["package"],
                  module: name,
                  function: Atom.to_string(function),
                  arity: arity,
                  source: Path.relative_to(source, package["worktree"]),
                  classification: classification,
                  generated_instance: template?,
                  failure: reason
                }
              end
            else
              []
            end
          end)

        {all ++ rows, failures ++ Enum.filter(rows, & &1.failure)}

      _ ->
        {all,
         failures ++ [%{package: package["package"], failure: "required_application_not_loaded"}]}
    end
  end)

expected_count = if phase == "G3", do: 2, else: 11

failures =
  if length(packages) == expected_count,
    do: failures,
    else: failures ++ [%{failure: "required_package_row_missing"}]

exports = Enum.sort_by(exports, &{&1.package, &1.module, &1.function, &1.arity})

result = %{
  gate: phase,
  state: if(failures == [], do: "pass", else: "fail"),
  scope: Enum.map(packages, & &1["package"]),
  export_count: length(exports),
  generated_instance_export_count: Enum.count(exports, & &1.generated_instance),
  inputs:
    Map.new(~w(api-map version-matrix catalog new-major-core-api core-retired-modules), fn file ->
      bytes = File.read!(Path.join(manifest_dir, file <> ".json"))
      {file, Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)}
    end),
  source_revisions:
    Map.new(packages, fn package ->
      root = package["worktree"]
      {head, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: root)

      sources =
        exports
        |> Enum.filter(&(&1.package == package["package"]))
        |> Enum.map(& &1.source)
        |> Enum.uniq()
        |> Enum.sort()

      fingerprint =
        Enum.map(sources, fn path -> [path, <<0>>, File.read!(Path.join(root, path)), <<0>>] end)
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)

      {package["package"],
       %{
         head_sha: String.trim(head),
         compiled_source_files: length(sources),
         source_sha256: fingerprint
       }}
    end),
  failures: failures,
  exports: exports,
  note:
    "This audit checks compiled API mappings and retired exports. Behavioral tests, all-adapter conformance, coverage, and current-head CI remain separate requirements."
}

output =
  Keyword.get(
    opts,
    :output,
    Path.join(manifest_dir, "new-major-#{String.downcase(phase)}-api.json")
  )

File.write!(output, Jason.encode!(result, pretty: true) <> "\n")
IO.puts(Jason.encode!(Map.drop(result, [:exports]), pretty: true))
if failures != [], do: System.halt(1)
