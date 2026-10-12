{opts, _, invalid} =
  OptionParser.parse(System.argv(), strict: [phase: :string, manifest: :string])

phase = Keyword.get(opts, :phase, "all")
manifest = Keyword.get(opts, :manifest, "../docs/migration/version-matrix.json")

if invalid != [] or phase not in ["G1", "all"] do
  IO.puts(
    Jason.encode!(%{
      state: "fail",
      errors: ["Use --phase G1 or --phase all and --manifest PATH."]
    })
  )

  System.halt(1)
end

result = Jido.Chat.Integration.Manifest.verify(Path.dirname(Path.expand(manifest)), phase)
IO.puts(Jason.encode!(result, pretty: true))
if result.state != "pass", do: System.halt(1)
