core = Path.expand("../..", __DIR__)
root = Path.dirname(core)

manifest =
  core |> Path.join("docs/migration/version-matrix.json") |> File.read!() |> Jason.decode!()

rows =
  for row <- manifest["packages"], Map.has_key?(row, "base_sha") do
    try do
      repository = Path.join(root, row["package"])

      archive =
        Path.join(
          System.get_env("JIDO_PACKAGE_ARTIFACT_DIR") || repository,
          row["package"] <> "-" <> row["declared_version"] <> ".tar"
        )

      {:ok, entries} = :erl_tar.extract(String.to_charlist(archive), [:memory])
      entries = Map.new(entries, fn {key, value} -> {to_string(key), value} end)

      {:ok, files} =
        :erl_tar.extract({:binary, entries["contents.tar.gz"]}, [:compressed, :memory])

      files = Map.new(files, fn {key, value} -> {to_string(key), value} end)

      temporary =
        Path.join(System.tmp_dir!(), "g7-package-#{System.unique_integer([:positive])}.config")

      File.write!(temporary, entries["metadata.config"])

      metadata =
        try do
          {:ok, terms} = :file.consult(String.to_charlist(temporary))
          Map.new(terms)
        after
          File.rm!(temporary)
        end

      library = Path.wildcard(Path.join(repository, "lib/**/*.ex"))

      true =
        Enum.all?(library, fn path ->
          files[Path.relative_to(path, repository)] == File.read!(path)
        end)

      forbidden = ~w(.env .git .agents .codex _build deps test cover)
      true = Enum.all?(Map.keys(files), fn path -> hd(Path.split(path)) not in forbidden end)

      requirements =
        Map.new(metadata["requirements"], fn fields ->
          fields = Map.new(fields)
          {fields["app"], fields}
        end)

      true =
        Enum.all?(requirements, fn {_, fields} ->
          is_binary(fields["requirement"]) and fields["repository"] == "hexpm"
        end)

      if row["package"] != "jido_chat",
        do: true = Version.match?("2.0.0", requirements["jido_chat"]["requirement"])

      if row["package"] in ["jido_chat", "jido_messaging"],
        do:
          true =
            Version.match?("3.0.0-beta.4", requirements["jido_signal"]["requirement"],
              allow_pre: true
            )

      %{
        package: row["package"],
        declared_version: metadata["version"],
        intended_version: row["intended_version"],
        archive_sha256: Base.encode16(:crypto.hash(:sha256, File.read!(archive)), case: :lower),
        state: "pass",
        library_bytes_match: true,
        no_private_files: true,
        production_requirements_valid: true,
        files: Enum.sort(Map.keys(files)),
        requirements: requirements,
        publication_ready: false,
        note: "Local build only. Release versions, availability and PR delivery remain in B6."
      }
    rescue
      error ->
        %{
          package: row["package"],
          state: "fail",
          errors: [Exception.message(error)],
          library_bytes_match: false,
          no_private_files: false,
          production_requirements_valid: false,
          publication_ready: false,
          build_evidence: "g7-#{row["package"]}-package-build.json"
        }
    end
  end

true = length(rows) == 10
state = if Enum.all?(rows, &(&1.state == "pass")), do: "pass", else: "fail"
output = System.fetch_env!("JIDO_CONFORMANCE_EVIDENCE") |> Path.join("package-index.json")
File.write!(output, Jason.encode!(%{state: state, packages: rows}, pretty: true) <> "\n")

IO.puts(
  Jason.encode!(%{
    state: state,
    verified_package_file_lists: Enum.count(rows, &(&1.state == "pass")),
    packages: length(rows)
  })
)

if state != "pass", do: System.halt(1)
