ExUnit.start(seed: 0, capture_log: true)

unless Code.ensure_loaded?(Jido.Chat.Telegram.Adapter),
  do: raise("Use JIDO_INTEGRATION_PROFILE=telegram_slack.")

Code.require_file(Path.expand("../fixtures/telegram_execution_runtime_test.exs", __DIR__))
