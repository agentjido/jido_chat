import Config

if config_env() in [:dev, :test] do
  config :covenant,
    contracts_dir: "test/contracts",
    test_paths: ["test/contracts/**/*_test.exs"],
    sibling_dir: false
end

if config_env() == :dev do
  config :git_hooks,
    auto_install: false,
    verbose: true,
    hooks: [
      commit_msg: [
        tasks: [
          {:cmd, "mix git_ops.check_message", include_hook_args: true}
        ]
      ]
    ]

  config :git_ops,
    mix_project: Jido.Chat.MixProject,
    repository_url: "https://github.com/agentjido/jido_chat",
    manage_mix_version?: true,
    version_tag_prefix: "v",
    types: [
      feat: [header: "Features"],
      fix: [header: "Bug Fixes"],
      perf: [header: "Performance"],
      refactor: [header: "Refactoring"],
      docs: [hidden?: true],
      test: [hidden?: true],
      chore: [hidden?: true],
      ci: [hidden?: true]
    ]
end

if config_env() in [:dev, :test] do
  config :spark, :formatter,
    remove_parens?: true,
    "Jido.Agent": [type: Jido.Agent.DSL, extensions: [Jido.Chat.Plugin]]
end
