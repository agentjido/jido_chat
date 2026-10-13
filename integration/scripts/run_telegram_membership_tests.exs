# G4 mapper verification. Full Telegram adapter and polling checks remain required.
root = Path.expand("../../..", __DIR__)
ExUnit.start(seed: 0, capture_log: true)

{_, diagnostics} =
  Code.with_diagnostics(fn ->
    Code.require_file(Path.join(root, "jido_chat_telegram/lib/jido/chat/telegram/membership.ex"))
  end)

if Enum.any?(diagnostics, &(&1.severity == :warning)), do: raise("Telegram membership mapper has compiler warnings")
Code.require_file(Path.join(root, "jido_chat_telegram/test/jido/chat/telegram/membership_test.exs"))
