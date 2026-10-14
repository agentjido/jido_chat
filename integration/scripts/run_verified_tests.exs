unless Code.ensure_loaded?(Jido.Chat.Integration.ReportFormatter) do
  Code.require_file(Path.expand("../lib/report_formatter.ex", __DIR__))
end

Mix.Task.run(
  "test",
  System.argv() ++
    [
      "--formatter",
      "ExUnit.CLIFormatter",
      "--formatter",
      "Jido.Chat.Integration.ReportFormatter"
    ]
)
