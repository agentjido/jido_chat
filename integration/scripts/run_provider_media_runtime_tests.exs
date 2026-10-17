# Run with the Telegram/Slack integration profile. No provider call is permitted.
ExUnit.start(seed: 0, capture_log: true)

unless Code.ensure_loaded?(Jido.Chat.Telegram.Adapter) and
         Code.ensure_loaded?(Jido.Chat.Slack.Adapter),
       do: raise("Use JIDO_INTEGRATION_PROFILE=telegram_slack or all.")

Code.require_file(Path.expand("../fixtures/provider_media_runtime_test.exs", __DIR__))
