# The mapper tests precede the full Slack adapter port. G5 still requires package/runtime conformance.
root = Path.expand("../../..", __DIR__)
ExUnit.start(seed: 0, capture_log: true)

{_, diagnostics} =
  Code.with_diagnostics(fn ->
    Code.require_file(Path.join(root, "jido_chat_slack/lib/jido/chat/slack/normalizer.ex"))
  end)

if Enum.any?(diagnostics, &(&1.severity == :warning)),
  do: raise("Slack normalizer has compiler warnings")

Code.require_file(Path.join(root, "jido_chat_slack/test/jido/chat/slack/normalizer_test.exs"))
