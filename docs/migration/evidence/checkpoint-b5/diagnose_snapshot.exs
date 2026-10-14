directory = System.fetch_env!("JIDO_CONFORMANCE_EVIDENCE")
index = Path.join(directory, "candidate-index.json") |> File.read!() |> Jason.decode!()
root = Path.expand("../..", File.cwd!())
for row <- index["packages"] do
 current = Jido.Chat.Integration.Conformance.snapshot(Path.join(root, row["package"]))
 for {scope, expected} <- row["source_snapshot"], current[scope] != expected do
  IO.puts(Jason.encode!(%{package: row["package"], scope: scope, expected: expected, actual: current[scope]}))
 end
end
