defmodule Jido.Chat.Integration.MixProject do
  use Mix.Project

  @moduledoc false
  @adapter_apps [
    :jido_chat_telegram,
    :jido_chat_slack,
    :jido_chat_discord,
    :jido_chat_github,
    :jido_chat_signal,
    :jido_chat_teams,
    :jido_chat_whatsapp,
    :jido_chat_x
  ]

  def project do
    [
      app: :jido_chat_integration,
      version: "0.0.0",
      elixir: "~> 1.18",
      deps: deps(),
      elixirc_paths: [
        "lib",
        Path.expand("../test/support", __DIR__),
        Path.expand("../../jido_messaging/test/support", __DIR__)
      ],
      test_paths: ["test"],
      test_ignore_filters: [
        ~r{(^|/)test/support/|_helper\.exs$|/optional/jido_ai_integration\.exs$}
      ],
      aliases: [
        "test.chat": "test ../test --exclude live --seed 0",
        "test.messaging":
          "test ../../jido_messaging/test --exclude flaky --exclude integration --exclude story --exclude live --seed 0"
      ]
    ]
  end

  def application, do: [extra_applications: [:logger, :ex_unit]]

  defp deps do
    manifest =
      __DIR__
      |> Path.join("../docs/migration/version-matrix.json")
      |> File.read!()
      |> :json.decode()

    graph = Map.fetch!(manifest, "upstream_graph")

    core = [
      {:jido_chat, path: "..", override: true},
      {:jido_messaging, path: "../../jido_messaging", override: true},
      git_dep(:jido_signal, graph),
      git_dep(:jido, graph),
      git_dep(:jido_action, graph),
      git_dep(:zoi, graph),
      {:runic, "== " <> graph["runic"]["version"], override: true},
      {:decimal, "== " <> graph["decimal"]["version"], override: true}
    ]

    selected_adapters =
      case System.get_env("JIDO_INTEGRATION_PROFILE", "all") do
        "all" ->
          @adapter_apps

        "runtime" ->
          [:jido_chat_signal]

        "telegram" ->
          [:jido_chat_signal, :jido_chat_telegram]

        "telegram_slack" ->
          [:jido_chat_signal, :jido_chat_telegram, :jido_chat_slack]

        other ->
          Mix.raise(
            "Unknown integration profile: #{other}. Use all, runtime, telegram, or telegram_slack."
          )
      end

    adapters =
      Enum.map(selected_adapters, fn app ->
        row = Enum.find(manifest["packages"], &(&1["package"] == Atom.to_string(app)))
        if is_nil(row), do: Mix.raise("Missing adapter source in version matrix: #{app}")
        root = System.get_env("JIDO_INTEGRATION_SOURCE_ROOT") || Path.expand("../..", __DIR__)
        path = Path.join(root, row["package"])

        if not File.regular?(Path.join(path, "mix.exs")),
          do: Mix.raise("Missing adapter checkout: #{app}")

        {app, path: path, override: true}
      end)

    core = core ++ adapters ++ [{:protobuf, "~> 0.17.0", override: true}]

    if System.get_env("JIDO_INTEGRATION_AI", "0") == "1" do
      core ++
        [
          git_dep(:jido_ai, graph),
          {:req_llm, "== " <> graph["req_llm"]["version"], override: true},
          {:llm_db, "== " <> graph["llm_db"]["version"], override: true}
        ]
    else
      core
    end
  end

  defp git_dep(app, graph) do
    source = Map.fetch!(graph, Atom.to_string(app))

    {app,
     git: "https://github.com/" <> source["repository"] <> ".git",
     ref: source["ref"],
     override: true}
  end
end
