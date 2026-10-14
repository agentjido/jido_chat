ExUnit.start(seed: 0, capture_log: true)
Code.require_file(Path.expand("run_b3_checkpoint_tests.exs", __DIR__))
Code.require_file(Path.expand("run_g6_checkpoint_tests.exs", __DIR__))
Code.require_file(Path.expand("../fixtures/g7_boundary_test.exs", __DIR__))

ExUnit.configure(formatters: [ExUnit.CLIFormatter, Jido.Chat.Integration.ReportFormatter])
