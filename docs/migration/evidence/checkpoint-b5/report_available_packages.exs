core = "/Users/mhostetler/Source/Jido/proj_jido_chat/.worktrees/public-signal-v3/jido_chat"
root = Path.dirname(core)

manifest =
  core |> Path.join("docs/migration/version-matrix.json") |> File.read!() |> Jason.decode!()

rows =
  for row <- manifest["packages"], Map.has_key?(row, "base_sha"), row["package"] != "jido_chat_mattermost" do
    repository = Path.join(root, row["package"])
    archive = Path.join(repository, row["package"] <> "-" <> row["declared_version"] <> ".tar")
    {:ok, entries} = :erl_tar.extract(String.to_charlist(archive), [:memory])
    entries = Map.new(entries, fn {key, value} -> {to_string(key), value} end)
    {:ok, files} = :erl_tar.extract({:binary, entries["contents.tar.gz"]}, [:compressed, :memory])
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
      Map.new(metadata["requirements"], fn {app, fields} -> {app, Map.new(fields)} end)

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
      library_bytes_match: true,
      no_private_files: true,
      production_requirements_valid: true,
      files: Enum.sort(Map.keys(files)),
      requirements: requirements,
      publication_ready: false,
      note: "Local build only. Release versions, availability and PR delivery remain in B6."
    }
  end

true = length(rows) == 10
rows = rows ++ [%{package: "jido_chat_mattermost", state: "fail", library_bytes_match: false, no_private_files: false, production_requirements_valid: false, errors: ["No license metadata. User specified no license.", "Fresh uses a Git dependency; Hex excludes it."], evidence: "g7-jido_chat_mattermost-package-build.json", publication_ready: false}]
output = System.fetch_env!("JIDO_CONFORMANCE_EVIDENCE") |> Path.join("package-index.json")
File.write!(output, Jason.encode!(%{state: "fail", verified_packages: 10, packages: rows}, pretty: true) <> "\n")
IO.puts(Jason.encode!(%{state: "fail", verified_package_file_lists: 10, blocked_packages: 1}))
