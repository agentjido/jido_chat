Code.require_file("../../test/jido/chat/v3_baseline_test.exs", __DIR__)

Code.require_file(
  "../../../jido_messaging/test/jido_messaging/native_signal_context_test.exs",
  __DIR__
)

defmodule Jido.Chat.Integration.BaselineTest do
  use ExUnit.Case, async: true

  test "one selected v3 runtime set is loaded" do
    assert Application.spec(:jido_signal, :vsn) |> to_string() == "3.0.0-beta.4"
    assert Application.spec(:jido, :vsn) |> to_string() == "3.0.0-beta.1"
    assert Application.spec(:jido_action, :vsn) |> to_string() == "3.0.0-beta.12"
    assert Application.spec(:zoi, :vsn) |> to_string() == "0.18.11"
    assert Code.ensure_loaded?(Jido.Executable)
    assert Code.ensure_loaded?(Jido.Signal.Catalog)
    refute Code.ensure_loaded?(Jido.Signal.Ext)
  end

  test "optional AI is present only in the selected profile" do
    if System.get_env("JIDO_INTEGRATION_AI", "0") == "1" do
      assert Code.ensure_loaded?(Jido.AI.Agent)
      assert Application.spec(:jido_ai, :vsn) |> to_string() == "2.3.0"
    else
      refute Code.ensure_loaded?(Jido.AI.Agent)
      refute Enum.any?(Application.loaded_applications(), fn {app, _, _} -> app == :jido_ai end)
    end
  end

  test "the selected package profile contains every required package" do
    runtime = [:jido_chat, :jido_messaging, :jido_chat_signal]

    expected =
      case System.get_env("JIDO_INTEGRATION_PROFILE", "all") do
        "runtime" ->
          runtime

        "telegram" ->
          runtime ++ [:jido_chat_telegram]

        "telegram_slack" ->
          runtime ++ [:jido_chat_telegram, :jido_chat_slack]

        "all" ->
          runtime ++
            [
              :jido_chat_telegram,
              :jido_chat_slack,
              :jido_chat_discord,
              :jido_chat_github,
              :jido_chat_teams,
              :jido_chat_whatsapp,
              :jido_chat_x
            ]
      end

    actual =
      Mix.Dep.cached()
      |> Enum.map(& &1.app)
      |> Enum.filter(fn app ->
        app == :jido_messaging or String.starts_with?(Atom.to_string(app), "jido_chat")
      end)

    assert MapSet.new(actual) == MapSet.new(expected)
  end
end
