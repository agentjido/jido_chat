defmodule Jido.Chat.Integration.SourceAPI do
  @moduledoc false
  def exports(ast),
    do:
      walk(ast, nil, false, [])
      |> Enum.uniq()
      |> Enum.sort_by(&{&1["module"], &1["function"], &1["arity"]})

  defp walk({:defmodule, _, [module, [do: body]]}, parent, generated, rows) do
    name = Macro.to_string(module)

    name =
      if parent && not String.starts_with?(name, "Jido."), do: parent <> "." <> name, else: name

    walk(body, name, generated, rows)
  end

  defp walk({kind, _, [head | body]}, module, generated, rows)
       when kind in [:def, :defdelegate, :defmacro, :defguard] do
    head =
      case head do
        {:when, _, [call | _]} -> call
        call -> call
      end

    rows =
      case head do
        {name, _, args} when is_atom(name) and (is_list(args) or is_nil(args)) ->
          args = args || []
          max = length(args)
          min = max - Enum.count(args, &match?({:\\, _, _}, &1))

          Enum.reduce(min..max, rows, fn arity, acc ->
            [
              %{
                "module" => module,
                "function" => Atom.to_string(name),
                "arity" => arity,
                "generated_template" => generated,
                "kind" => Atom.to_string(kind),
                "classification" => "pending",
                "replacement" => nil
              }
              | acc
            ]
          end)

        _ ->
          rows
      end

    if kind == :defmacro, do: walk(body, module, true, rows), else: rows
  end

  defp walk(tuple, module, generated, rows) when is_tuple(tuple),
    do: walk(Tuple.to_list(tuple), module, generated, rows)

  defp walk(list, module, generated, rows) when is_list(list),
    do: Enum.reduce(list, rows, &walk(&1, module, generated, &2))

  defp walk(_, _, _, rows), do: rows
end

manifest_path = Path.expand("../docs/migration/version-matrix.json")
manifest = manifest_path |> File.read!() |> Jason.decode!()

rows =
  manifest["packages"]
  |> Enum.filter(&Map.has_key?(&1, "base_sha"))
  |> Enum.flat_map(fn row ->
    {paths, 0} =
      System.cmd("git", ["ls-tree", "-r", "--name-only", row["base_sha"], "lib"],
        cd: row["worktree"]
      )

    paths
    |> String.split("\n", trim: true)
    |> Enum.filter(&String.ends_with?(&1, ".ex"))
    |> Enum.flat_map(fn path ->
      {source, 0} =
        System.cmd("git", ["show", row["base_sha"] <> ":" <> path], cd: row["worktree"])

      source
      |> Code.string_to_quoted!()
      |> Jido.Chat.Integration.SourceAPI.exports()
      |> Enum.map(
        &Map.merge(&1, %{
          "package" => row["package"],
          "source" => path,
          "base_sha" => row["base_sha"]
        })
      )
    end)
  end)

output = Path.expand("../docs/migration/source-api.json")

File.write!(
  output,
  Jason.encode!(
    %{
      "protocol_version" => 1,
      "state" => "draft",
      "exports" => rows,
      "inventory_rule" =>
        "Source exports and quoted macro templates at each verified base. Audit generated runtime exports before G1 passes."
    },
    pretty: true
  ) <> "\n"
)

IO.puts(Jason.encode!(%{state: "draft", export_count: length(rows)}))
