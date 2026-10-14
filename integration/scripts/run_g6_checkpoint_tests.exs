ExUnit.start(seed: 0, capture_log: true)

for {package, path} <- [
      {"discord", "jido/chat/discord"},
      {"github", "jido/chat/github"},
      {"signal", "jido_chat_signal"},
      {"mattermost", "jido/chat/mattermost"},
      {"teams", "jido/chat/teams"},
      {"whatsapp", "jido/chat/whatsapp"},
      {"x", "jido/chat/x"}
    ] do
  file = if package == "signal", do: "adapter_test.exs", else: "protocol_test.exs"
  Code.require_file(Path.expand("../../../jido_chat_#{package}/test/#{path}/#{file}", __DIR__))
end

Code.require_file(Path.expand("../fixtures/g6_adapter_checkpoint_test.exs", __DIR__))
