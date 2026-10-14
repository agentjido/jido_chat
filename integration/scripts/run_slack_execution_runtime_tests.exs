# Run against the real Slack adapter, core, and Messaging in the pinned graph.
root = Path.expand("../../..", __DIR__)
ExUnit.start(seed: 0, capture_log: true)

unless Code.ensure_loaded?(Jido.Chat.Slack.Adapter),
  do: raise("Use JIDO_INTEGRATION_PROFILE=telegram_slack or all.")

Code.require_file(
  Path.join(root, "jido_chat/integration/fixtures/slack_execution_runtime_test.exs")
)
