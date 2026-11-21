ExUnit.start(
  exclude: [:live],
  assert_receive_timeout: 1_000,
  formatters: [ExUnit.CLIFormatter, Covenant.Formatter, Jido.Chat.LiveCase.Formatter]
)

Jido.Chat.LiveCase.init_halts()

Code.require_file("contracts/support/fixtures_helper.exs", __DIR__)
Code.require_file("support/providers/telegram/fixtures_helper.exs", __DIR__)
