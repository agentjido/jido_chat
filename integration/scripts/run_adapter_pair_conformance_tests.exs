ExUnit.start(seed: 0, capture_log: true)

unless Code.ensure_loaded?(Jido.Chat.Telegram.Adapter) and Code.ensure_loaded?(Jido.Chat.Slack.Adapter),
  do: raise("Use JIDO_INTEGRATION_PROFILE=telegram_slack.")

Code.require_file(Path.expand("../fixtures/adapter_pair_conformance_test.exs", __DIR__))
