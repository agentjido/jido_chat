# Run from the Signal provider project after a successful compile with the local core path.
core = Path.expand("../..", __DIR__)
old = core |> Path.join("docs/migration/api-map.json") |> File.read!() |> Jason.decode!()

retired =
  core
  |> Path.join("docs/migration/core-retired-modules.json")
  |> File.read!()
  |> Jason.decode!()
  |> Map.fetch!("modules")

rows =
  for app <- [:jido_chat, :jido_chat_signal],
      module <- Application.spec(app, :modules),
      Code.ensure_loaded?(module),
      source = module.module_info(:compile)[:source] |> to_string(),
      String.contains?(source, "/lib/"),
      {function, arity} <- module.__info__(:functions) ++ module.__info__(:macros),
      function not in [:__struct__, :__info__, :module_info] do
    name = module |> Atom.to_string() |> String.trim_leading("Elixir.")

    previous =
      Enum.find(
        old["exports"],
        &(&1["module"] == name and &1["function"] == Atom.to_string(function) and
            &1["arity"] == arity)
      )

    classification =
      cond do
        name == "Jido.Chat" and function in [:bind, :execute, :normalize_event] ->
          "request-result"

        function_exported?(module, :__signal_owner__, 0) ->
          "request-result"

        previous ->
          previous["classification"]

        true ->
          "private-implementation"
      end

    %{
      package: Atom.to_string(app),
      module: name,
      function: Atom.to_string(function),
      arity: arity,
      classification: classification,
      definition_kind:
        if(function_exported?(module, :__signal_kind__, 0), do: module.__signal_kind__()),
      source: Path.relative_to(source, Path.dirname(core))
    }
  end

rows = Enum.sort_by(rows, &{&1.package, &1.module, &1.function, &1.arity})
true = Enum.all?(rows, &(&1.module not in retired))

false =
  Enum.any?(
    rows,
    &(&1.module == "Jido.Chat" and
        &1.function in ~w(new process_message process_event route_event route_request handle_webhook handle_webhook_request))
  )

result = %{
  gate: "G2",
  state: "pass",
  scope: "compiled core and Signal provider library exports",
  export_count: length(rows),
  exports: rows
}

File.write!(
  Path.join(core, "docs/migration/new-major-core-api.json"),
  Jason.encode!(result, pretty: true) <> "\n"
)

IO.puts(Jason.encode!(Map.drop(result, [:exports]), pretty: true))
