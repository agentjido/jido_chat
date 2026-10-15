ExUnit.start(seed: 0, capture_log: true)

unless Code.ensure_loaded?(Jido.Chat.Telegram.Adapter) and
         Code.ensure_loaded?(Jido.Chat.Slack.Adapter),
       do: raise("Use JIDO_INTEGRATION_PROFILE=telegram_slack.")

for fixture <-
      ~w(adapter_pair_conformance_test telegram_membership_runtime_test slack_membership_schema_test slack_membership_runtime_test telegram_execution_runtime_test slack_execution_runtime_test provider_media_runtime_test) do
  Code.require_file(Path.expand("../fixtures/#{fixture}.exs", __DIR__))
end

for {package, provider} <- [{"jido_chat_telegram", "telegram"}, {"jido_chat_slack", "slack"}] do
  Code.require_file(
    Path.expand(
      "../../../#{package}/test/jido/chat/#{provider}/operation_matrix_test.exs",
      __DIR__
    )
  )
end
