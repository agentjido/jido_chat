result = Jido.Chat.Integration.Conformance.run()
directory = System.fetch_env!("JIDO_CONFORMANCE_EVIDENCE")

File.write!(
  Path.join(directory, "conformance-report.json"),
  Jason.encode!(result, pretty: true) <> "\n"
)

IO.puts(
  Jason.encode!(
    %{
      state: result.state,
      assertions: Map.new(result.assertions, fn {id, row} -> {id, row.state} end),
      failed_checks: Enum.filter(result.mandatory_checks, &(&1.state != "pass"))
    },
    pretty: true
  )
)

if result.state != "pass", do: System.halt(1)
