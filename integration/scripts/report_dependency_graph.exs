manifest =
  Path.expand("../../docs/migration/version-matrix.json", __DIR__)
  |> File.read!()
  |> Jason.decode!()

expected = manifest["upstream_graph"]

rows =
  Mix.Dep.cached()
  |> Enum.map(fn dep ->
    version =
      case dep.status do
        {:ok, value} -> to_string(value)
        other -> inspect(other)
      end

    actual_ref =
      if dep.opts[:git] do
        {ref, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: dep.opts[:dest])
        {dirty, 0} = System.cmd("git", ["status", "--porcelain"], cd: dep.opts[:dest])
        true = dirty == ""
        String.trim(ref)
      end

    source_tree =
      if dep.opts[:path] do
        root = dep.opts[:dest]
        {head, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: root)

        files =
          (Path.wildcard(Path.join(root, "lib/**/*.ex")) ++ Path.wildcard(Path.join(root, "test/**/*.{ex,exs}")))
          |> Enum.sort()

        digest =
          Enum.map(files, &[Path.relative_to(&1, root), <<0>>, File.read!(&1), <<0>>])
          |> then(&:crypto.hash(:sha256, &1))
          |> Base.encode16(case: :lower)

        %{"head_sha" => String.trim(head), "library_test_files" => length(files), "library_test_sha256" => digest}
      end

    %{
      "app" => Atom.to_string(dep.app),
      "version" => version,
      "git" => dep.opts[:git],
      "ref" => dep.opts[:ref],
      "actual_ref" => actual_ref,
      "path_source" => source_tree,
      "hex" => if(dep.scm == Hex.SCM, do: Atom.to_string(dep.app)),
      "children" => Enum.map(dep.deps, &Atom.to_string(&1.app))
    }
  end)
  |> Enum.sort_by(& &1["app"])

for app <- ["jido_signal", "jido", "jido_action", "zoi"] do
  [row] = Enum.filter(rows, &(&1["app"] == app))
  true = row["ref"] == expected[app]["ref"]
  true = row["actual_ref"] == row["ref"]
  true = row["version"] == expected[app]["declared_version"]
end

with_ai = System.get_env("JIDO_INTEGRATION_AI", "0") == "1"
true = Enum.any?(rows, &(&1["app"] == "jido_ai")) == with_ai

if with_ai do
  [row] = Enum.filter(rows, &(&1["app"] == "jido_ai"))
  true = row["ref"] == expected["jido_ai"]["ref"]
  true = row["actual_ref"] == row["ref"]
end

for {app, source} <- expected, source["hex"] != nil, source["optional"] != true or with_ai do
  [row] = Enum.filter(rows, &(&1["app"] == app))
  true = row["version"] == source["version"]
end

profile = if with_ai, do: "with-ai", else: "core-only"
scope = System.get_env("JIDO_INTEGRATION_PROFILE", "all")
core = Path.expand("../..", __DIR__)

output =
  System.get_env("JIDO_INTEGRATION_GRAPH_OUTPUT") ||
    Path.join(core, "docs/migration/evidence/g0/graph-#{scope}-#{profile}.json")

result = %{
  "state" => "pass",
  "profile" => profile,
  "package_scope" => scope,
  "dependencies" => rows,
  "note" =>
    case scope do
      "runtime" -> "Core, Messaging, and the Signal provider. All nine adapters remain required for G7."
      "telegram" -> "Core, Messaging, Signal provider, and Telegram. All nine adapters remain required for G7."
      "all" -> "Whole-group dependency graph."
    end
}

File.write!(output, Jason.encode!(result, pretty: true) <> "\n")
IO.puts(Jason.encode!(%{state: "pass", profile: profile, dependency_count: length(rows)}))
