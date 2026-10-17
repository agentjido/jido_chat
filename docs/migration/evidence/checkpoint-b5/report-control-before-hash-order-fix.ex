defmodule Jido.Chat.Integration.Conformance do
  @moduledoc "Checks C01–C14 against current source files and individual fixture results."
  @core Path.expand("../..", __DIR__)
  @root Path.dirname(@core)
  @docs Path.join(@core, "docs/migration")
  @ids Enum.map(1..14, &("C" <> String.pad_leading(to_string(&1), 2, "0")))
  @scopes ~w(lib test integration/lib integration/test integration/scripts integration/fixtures integration/examples)
  @files ~w(mix.exs mix.lock config/config.exs config/test.exs)
  @cache {__MODULE__, :run_cache}
  @packages ~w(jido_chat jido_messaging jido_chat_telegram jido_chat_slack jido_chat_discord jido_chat_github jido_chat_signal jido_chat_mattermost jido_chat_teams jido_chat_whatsapp jido_chat_x)

  def run, do: run([])

  def run(opts) do
    previous = Process.get(@cache, :absent)
    Process.put(@cache, %{})

    try do
      run_report(opts)
    after
      if previous == :absent, do: Process.delete(@cache), else: Process.put(@cache, previous)
    end
  end

  defp run_report(opts) do
    directory =
      opts[:evidence_directory] || System.get_env("JIDO_CONFORMANCE_EVIDENCE") ||
        Path.join(@docs, "evidence/checkpoint-b5")

    with {:ok,
          %{
            "case_commands" => %{},
            "mandatory_commands" => required,
            "coverage_commands" => coverage
          } = inputs} <- read(Path.join(directory, "inputs.json")),
         true <- is_list(required) and is_list(coverage) do
      assertions = Map.new(@ids, fn id -> {id, assess(id, inputs, directory)} end)

      checks =
        Enum.map(inputs["mandatory_commands"], &assess_command(&1, directory)) ++
          Enum.map(inputs["coverage_commands"], &assess_coverage(&1, directory))

      expected =
        for package <- @packages,
            task <- ~w(suite quality audit unused-lock package-build),
            do: "g7-#{package}-#{task}"

      complete = Enum.all?(expected, &(&1 in required)) and length(coverage) == 3

      checks = [
        %{command: "required package check list", state: if(complete, do: "pass", else: "fail")}
        | checks
      ]

      state =
        if Enum.all?(assertions, fn {_, row} -> row.state == "pass" end) and
             Enum.all?(checks, &(&1.state == "pass")), do: "pass", else: "fail"

      %{
        state: state,
        assertions: assertions,
        mandatory_checks: checks,
        source_scope:
          "Exact library, test, harness, Mix and configuration bytes; local fixtures only."
      }
    else
      _ ->
        %{
          state: "fail",
          assertions:
            Map.new(@ids, &{&1, %{state: "fail", errors: ["Missing conformance inputs."]}}),
          mandatory_checks: []
        }
    end
  end

  defp assess(id, inputs, directory) do
    selectors = json!(Path.join(@core, "integration/fixtures/conformance-cases.json"))[id]
    true = is_list(selectors)
    cases = Enum.map(selectors, &case_result!(&1, inputs, directory))
    measured = measure!(id, inputs, directory)
    %{state: "pass", fixtures: cases, measurements: measured}
  rescue
    error -> %{state: "fail", errors: [Exception.message(error)]}
  catch
    {:conformance, message} -> %{state: "fail", errors: [message]}
  end

  defp case_result!(selector, inputs, directory) do
    label =
      inputs["case_commands"][selector["category"]] ||
        fail!("Missing case command #{selector["category"]}.")

    command = command!(directory, label)
    true = command["exit_status"] == 0
    metadata = command["test_cases"] || fail!("No individual fixture results: #{label}.")
    path = Path.join(@docs, metadata["path"])
    verify_hash!(path, metadata["sha256"])
    rows = cached({:cases, path}, fn -> json!(path)["cases"] end)

    row =
      Enum.find(
        rows,
        &(Path.relative_to(&1["file"], @root) == selector["file"] and
            &1["name"] == "test " <> selector["name"])
      ) || fail!("Missing fixture: #{selector["file"]}: #{selector["name"]}.")

    if row["state"] != "pass",
      do: fail!("Fixture did not pass: #{row["name"]} (#{row["state"]}).")

    Map.merge(row, %{"command" => label, "cases_sha256" => metadata["sha256"]})
  end

  defp measure!("C01", _inputs, _directory) do
    entries = json!(Path.join(@docs, "catalog.json"))["definitions"]
    definitions = Jido.Chat.signal_definitions() ++ Jido.Messaging.signal_definitions()
    true = length(entries) == length(definitions)
    catalog = Jido.Signal.Catalog.new!(definitions)

    for entry <- entries do
      module = Module.concat([entry["module"]])
      {:ok, signal} = module.new(entry["fixture"], entry["fixture_options"])

      true =
        signal.type == entry["type"] and signal.dataschema == entry["dataschema"] and
          signal.data == entry["fixture"]

      {:ok, ^signal} = Jido.Signal.Catalog.validate(catalog, signal)
      {:ok, encoded} = Jido.Signal.Serialization.serialize(signal)
      {:ok, ^signal} = Jido.Signal.Catalog.decode(catalog, encoded)
    end

    %{validated_definitions: length(entries), native_round_trip: true}
  end

  defp measure!("C06", inputs, directory) do
    matrix = json!(Path.join(@docs, "adapter-matrix.json"))
    selectors = json!(Path.join(@core, "integration/fixtures/conformance-operations.json"))

    rows =
      for adapter <- matrix["adapters"], {operation, support} <- adapter["operation_support"] do
        selector =
          selectors[adapter["package"]][operation] ||
            fail!("Missing operation fixture #{adapter["package"]}:#{operation}.")

        true = selector["support"] == support
        result = case_result!(selector, inputs, directory)
        %{package: adapter["package"], operation: operation, support: support, fixture: result}
      end

    true = length(matrix["adapters"]) == 9 and length(rows) == 234
    %{operation_rows: rows}
  end

  defp measure!("C12", inputs, directory) do
    matrix = json!(Path.join(@docs, "adapter-matrix.json"))

    for row <- matrix["adapters"] do
      module = Module.concat([row["adapter_module"]])
      :ok = Jido.Chat.Adapter.validate_capabilities(module)
      capabilities = Jido.Chat.Adapter.capabilities(module)

      for {operation, support} <- row["operation_support"],
          do: true = Atom.to_string(capabilities[String.to_existing_atom(operation)]) == support
    end

    selectors = json!(Path.join(@core, "integration/fixtures/conformance-events.json"))

    for row <- matrix["adapters"], {event, support} <- row["event_support"] do
      selector = selectors[row["package"]][event]
      true = selector["support"] == support
      _ = case_result!(selector, inputs, directory)
    end

    scan = json!(Path.join(directory, inputs["boundary_scan"]))
    true = scan["state"] == "pass" and scan["findings"] == [] and length(scan["scope"]) == 11

    for row <- scan["source_revisions"],
        do:
          true =
            row["checked_source_sha256"] ==
              tree_hash(Path.join(@root, row["repository"]), "lib")["sha256"]

    api = json!(Path.join(directory, inputs["api_audit"]))
    true = api["state"] == "pass" and api["failures"] == [] and length(api["scope"]) == 11
    %{adapters: 9, source_files: scan["checked_files"], compiled_exports: api["export_count"]}
  end

  defp measure!("C13", inputs, directory) do
    selectors = json!(Path.join(@core, "integration/fixtures/conformance-cases.json"))

    for {id, rows} <- selectors,
        id in ~w(C01 C02 C03 C04 C05 C07 C08 C09 C10 C11 C12),
        row <- rows do
      _ = case_result!(Map.update!(row, "category", &(&1 <> "_ai")), inputs, directory)
    end

    graphs = Enum.map(inputs["graphs"], &json!(Path.join(directory, &1)))
    expected = json!(Path.join(@docs, "version-matrix.json"))["upstream_graph"]

    for graph <- graphs do
      true = graph["state"] == "pass" and graph["package_scope"] == "all"
      rows = graph["dependencies"]

      for app <- ~w(jido_signal jido jido_action zoi) do
        [row] = Enum.filter(rows, &(&1["app"] == app))

        true =
          row["actual_ref"] == expected[app]["ref"] and
            row["version"] == expected[app]["declared_version"]
      end

      true = Enum.count(rows, &(&1["path_source"] != nil)) == 11
      true = Enum.any?(rows, &(&1["app"] == "jido_ai")) == (graph["profile"] == "with-ai")

      if graph["profile"] == "with-ai" do
        [ai] = Enum.filter(rows, &(&1["app"] == "jido_ai"))
        true = ai["actual_ref"] == expected["jido_ai"]["ref"]
      end
    end

    true = Enum.sort(Enum.map(graphs, & &1["profile"])) == ["core-only", "with-ai"]

    for label <- inputs["profile_commands"],
        do: true = command!(directory, label)["exit_status"] == 0

    %{profiles: ["core-only", "with-ai"], packages_per_profile: 11}
  end

  defp measure!("C14", inputs, directory) do
    packages = json!(Path.join(directory, inputs["package_index"]))

    if packages["state"] != "pass" do
      failed = Enum.filter(packages["packages"], &(&1["state"] != "pass"))

      fail!(
        "Package file list/production metadata failed: " <>
          Enum.map_join(failed, ", ", & &1["package"])
      )
    end

    true = length(packages["packages"]) == 11

    for package <- packages["packages"],
        do:
          true =
            package["library_bytes_match"] and package["no_private_files"] and
              package["production_requirements_valid"]

    index = json!(Path.join(directory, inputs["candidate_index"]))
    true = length(index["packages"]) == 11 and index["PR_delivery"] == "pending_B6"

    for row <- index["packages"] do
      true = row["source_snapshot"] == snapshot(Path.join(@root, row["package"]))
      true = row["branch"] == "codex/public-signal-v3" and is_binary(row["rollback_pin"])
      true = row["pr_url"] == nil and row["ci_state"] == "not_started"
    end

    true = command!(directory, inputs["example_command"])["exit_status"] == 0

    %{
      package_file_lists: 11,
      production_metadata: "validated",
      local_candidate_index: "complete",
      pr_delivery: "pending_B6",
      publication_ready: false
    }
  end

  defp measure!(_id, _inputs, _directory), do: %{}

  defp assess_command(label, directory) do
    record = command!(directory, label)

    %{
      command: label,
      state: if(record["exit_status"] == 0, do: "pass", else: "fail"),
      exit_status: record["exit_status"]
    }
  rescue
    error -> %{command: label, state: "fail", errors: [Exception.message(error)]}
  catch
    {:conformance, message} -> %{command: label, state: "fail", errors: [message]}
  end

  defp assess_coverage(requirement, directory) do
    label = requirement["command"]
    record = command!(directory, label)

    expected_floor =
      %{"jido_messaging" => 90, "jido_chat_mattermost" => 90, "jido_chat_whatsapp" => 80}[
        record["repository"]
      ]

    true = requirement["floor"] == expected_floor
    measured = record["coverage_line_totals"]["percent"]
    true = is_number(measured)

    %{
      command: label,
      state:
        if(record["exit_status"] == 0 and measured >= expected_floor, do: "pass", else: "fail"),
      percent: measured,
      floor: expected_floor
    }
  rescue
    error -> %{command: requirement["command"], state: "fail", errors: [Exception.message(error)]}
  catch
    {:conformance, message} ->
      %{command: requirement["command"], state: "fail", errors: [message]}
  end

  defp command!(directory, label) do
    cached({:command, directory, label}, fn ->
      command = json!(Path.join(directory, label <> ".json"))
      verify_hash!(Path.join(@docs, command["log"]), command["log_sha256"])
      true = Enum.sort(Map.keys(command["sources_at_end"])) == Enum.sort(@packages)

      for {package, recorded} <- command["sources_at_end"] do
        current = cached({:source, package}, fn -> snapshot(Path.join(@root, package)) end)

        for scope <- @scopes ++ @files,
            Map.has_key?(recorded, scope),
            do: true = recorded[scope] == current[scope]
      end

      command
    end)
  end

  defp cached(key, function) do
    cache = Process.get(@cache, %{})

    case Map.fetch(cache, key) do
      {:ok, value} ->
        value

      :error ->
        value = function.()
        Process.put(@cache, Map.put(Process.get(@cache, %{}), key, value))
        value
    end
  end

  def snapshot(root) do
    Enum.reduce(@files, Map.new(@scopes, &{&1, tree_hash(root, &1)}), fn name, result ->
      path = Path.join(root, name)
      if File.regular?(path), do: Map.put(result, name, hash(File.read!(path))), else: result
    end)
  end

  defp tree_hash(root, scope) do
    files =
      Path.wildcard(Path.join([root, scope, "**", "*"]))
      |> Enum.filter(&File.regular?/1)
      |> Enum.sort()

    bytes = Enum.map(files, &[Path.relative_to(&1, root), <<0>>, File.read!(&1), <<0>>])
    %{"files" => length(files), "sha256" => hash(bytes)}
  end

  defp hash(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp verify_hash!(path, expected),
    do: if(hash(File.read!(path)) != expected, do: fail!("Changed evidence file: #{path}."))

  defp fail!(message), do: throw({:conformance, message})
  defp read(path), do: with({:ok, bytes} <- File.read(path), do: Jason.decode(bytes))
  defp json!(path), do: path |> File.read!() |> Jason.decode!()
end
