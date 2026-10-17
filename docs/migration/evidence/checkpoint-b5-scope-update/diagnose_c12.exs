core=Path.expand("..", File.cwd!()); root=Path.dirname(core); docs=Path.join(core,"docs/migration"); e=System.fetch_env!("JIDO_CONFORMANCE_EVIDENCE")
read=fn path -> path |> File.read!() |> Jason.decode!() end
matrix=read.(Path.join(docs,"adapter-matrix.json")); selectors=read.(Path.join(core,"integration/fixtures/conformance-events.json"))
for row <- matrix["adapters"] do
 module=Module.concat([row["adapter_module"]]); caps=Jido.Chat.Adapter.capabilities(module)
 bad=for {op,support} <- row["operation_support"], Atom.to_string(caps[String.to_existing_atom(op)]) != support, do: op
 events=for {event,support} <- row["event_support"], selectors[row["package"]][event]["support"] != support, do: event
 IO.puts(Jason.encode!(%{package: row["package"],capset: inspect(Jido.Chat.Adapter.validate_capabilities(module)),bad_ops: bad,bad_events: events}))
end
scan=read.(Path.join(e,"prohibited-boundary-scan.json"))
for row <- scan["source_revisions"] do
 actual=Jido.Chat.Integration.Conformance.snapshot(Path.join(root,row["repository"]))["lib"]["sha256"]
 IO.puts(Jason.encode!(%{package: row["repository"],hash_match: actual==row["checked_source_sha256"]}))
end
