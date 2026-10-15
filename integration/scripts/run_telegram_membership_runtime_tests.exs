# Run in the compiled Telegram integration profile. All nine adapters remain required for G7.
root = Path.expand("../../..", __DIR__)
ExUnit.start(seed: 0, capture_log: true)

unless Code.ensure_loaded?(Jido.Chat.Telegram.Adapter),
  do: raise("Use JIDO_INTEGRATION_PROFILE=telegram or all.")

Code.require_file(
  Path.join(root, "jido_chat/integration/fixtures/telegram_membership_runtime_test.exs")
)
