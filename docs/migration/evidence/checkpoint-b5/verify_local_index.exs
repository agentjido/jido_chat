directory = System.fetch_env!("JIDO_CONFORMANCE_EVIDENCE")
index = Path.join(directory, "candidate-index.json") |> File.read!() |> Jason.decode!()
true = index["PR_delivery"] == "pending_B6" and length(index["packages"]) == 11
root = Path.expand("../..", File.cwd!())
for row <- index["packages"] do
 true = row["source_snapshot"] == Jido.Chat.Integration.Conformance.snapshot(Path.join(root, row["package"]))
 true = row["branch"] == "codex/public-signal-v3" and is_binary(row["rollback_pin"])
 true = row["rollback_pin"] == row["base_sha"]
 {_, 0} = System.cmd("git", ["-C", Path.join(root, row["package"]), "cat-file", "-e", row["rollback_pin"] <> "^{commit}"])
 true = row["pr_url"] == nil and row["ci_state"] == "not_started"
 for {_, evidence} <- row["evidence"], do: true = File.regular?(Path.join(directory, evidence))
end
IO.puts(Jason.encode!(%{state: "pass", packages: 11, PR_delivery: "pending_B6", publication_ready: false}))
