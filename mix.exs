defmodule Jido.Chat.MixProject do
  use Mix.Project

  @version "3.0.0-dev"
  @source_url "https://github.com/agentjido/jido_chat"
  @description "Core chat SDK types and adapter contracts for the Jido ecosystem"

  def project do
    [
      app: :jido_chat,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "Jido Chat",
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),
      test_coverage: [
        tool: ExCoveralls,
        summary: [threshold: 90],
        export: "cov"
      ],
      dialyzer: [
        plt_local_path: "priv/plts/project.plt",
        plt_core_path: "priv/plts/core.plt",
        plt_add_apps: [:mix, :ex_unit, :jido]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        quality: :test,
        q: :test,
        "test.contracts": :test,
        cover: :test,
        coveralls: :test,
        "coveralls.github": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # SDK: execution, Signals, JSON, schemas, and errors.
      {:jido_action, "~> 3.0.0-beta.20", override: true},
      {:jido_signal, "~> 3.0.0-beta.5"},
      # Keep Jido V3's local development overrides on public Hex packages.
      {:runic, "~> 0.1.0-alpha.12", override: true},
      {:jason, "~> 1.4"},
      {:zoi, "~> 0.18.11"},
      {:splode, "~> 0.3.0"},

      # Agent Plugin and DSL. The host starts Jido when it activates the Plugin.
      {:jido, github: "agentjido/jido", ref: "7f4b806052440ef4278dd6826e787afb62c23899", runtime: false},
      {:spark, "~> 2.7", runtime: false},

      # Tests and coverage.
      {:covenant, "~> 0.2.0", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},

      # Formatting, static checks, and documentation.
      {:sourceror, "~> 1.7", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.4", only: :dev, runtime: false},

      # Optional local hooks and release commands.
      {:git_hooks, "~> 0.8", only: :dev, runtime: false},
      {:git_ops, "~> 2.9", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      install_hooks: ["git_hooks.install"],
      q: ["quality"],
      "test.contracts": ["covenant.check"],
      cover: ["coveralls"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --min-priority higher",
        "dialyzer",
        "doctor --raise"
      ]
    ]
  end

  defp package do
    [
      files: [
        "lib",
        "guides",
        "mix.exs",
        "README.md",
        "LICENSE",
        "CHANGELOG.md",
        "usage-rules.md"
      ],
      maintainers: ["Mike Hostetler"],
      licenses: ["Apache-2.0"],
      links: %{
        "Discord" => "https://jido.run/discord",
        "Documentation" => "https://hexdocs.pm/jido_chat",
        "GitHub" => @source_url,
        "Website" => "https://jido.run"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "guides/adapter_test_kit.md",
        "guides/contracts.md",
        "guides/static_sdk.md",
        "guides/public_api.md",
        "guides/source_layout.md"
      ]
    ]
  end
end
