Code.require_file(
  Path.expand("../../../jido_messaging/test/optional/jido_ai_integration.exs", __DIR__)
)

ExUnit.configure(formatters: [ExUnit.CLIFormatter, Jido.Chat.Integration.ReportFormatter])
