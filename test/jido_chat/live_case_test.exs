defmodule Jido.Chat.LiveCaseTest do
  use ExUnit.Case, async: false

  alias Jido.Chat.LiveCase
  alias Jido.Chat.Discord.LiveFixture, as: DiscordFixture
  alias Jido.Chat.Telegram.LiveFixture
  alias LiveFixture.Tracker

  @selector "JIDO_CHAT_LIVE_PROVIDERS"
  @legacy "RUN_LIVE_TELEGRAM_TESTS"
  @manual "RUN_LIVE_TELEGRAM_UI_TESTS"

  defmodule FixtureTransport do
    @behaviour Jido.Chat.Telegram.Transport

    @impl true
    def call(_token, method, payload, opts) do
      result = reply(method, payload)
      payload = if Keyword.get(opts, :mismatched_witness?), do: Map.put(payload, "text", "unexpected"), else: payload
      send(Keyword.fetch!(opts, :live_observer), {:telegram_live_wire, method, payload, result})
      result
    end

    defp reply("sendMessage", payload) do
      {:ok,
       %{
         "message_id" => 42,
         "message_thread_id" => payload["message_thread_id"],
         "chat" => %{"id" => String.to_integer(payload["chat_id"]), "type" => "private"},
         "text" => payload["text"]
       }}
    end

    defp reply("deleteMessage", _), do: {:ok, true}
    defp reply("createForumTopic", %{"chat_id" => "123"}), do: {:error, {:rejected, :provider_failure, %{}}}
    defp reply("createForumTopic", %{"name" => name}), do: {:ok, %{"message_thread_id" => 5, "name" => name}}
  end

  defmodule FixtureBot do
    def send_message("123", "local only", _opts), do: {:ok, %{"message_id" => 42}}
  end

  test "the shared and legacy selectors are mutually exclusive even with credentials loaded" do
    env(@selector, nil)
    env(@legacy, nil)
    env("TELEGRAM_BOT_TOKEN", "local-credential-sentinel")
    spec = case_spec("P01")

    assert {:inactive, _} = LiveCase.eligibility(LiveFixture, spec, :shared)
    assert {:inactive, _} = LiveCase.eligibility(LiveFixture, spec, :legacy)

    assert_raise ExUnit.AssertionError, ~r/live check inactive/, fn ->
      LiveCase.run(LiveFixture, spec, :atomics.new(1, []), :shared)
    end

    System.put_env(@legacy, "true")
    assert :ready = LiveCase.eligibility(LiveFixture, spec, :legacy)
    assert {:inactive, _} = LiveCase.eligibility(LiveFixture, spec, :shared)

    System.put_env(@selector, "telegram")
    assert :ready = LiveCase.eligibility(LiveFixture, spec, :shared)
    assert {:inactive, _} = LiveCase.eligibility(LiveFixture, spec, :legacy)

    assert_raise ExUnit.AssertionError, ~r/live check inactive/, fn ->
      LiveCase.run(LiveFixture, spec, :atomics.new(1, []), :legacy)
    end
  end

  test "the selector rejects unavailable providers without echoing the value" do
    assert LiveCase.selected_providers("telegram, telegram") == ["telegram"]

    assert_raise ArgumentError, "JIDO_CHAT_LIVE_PROVIDERS accepts telegram, discord", fn ->
      LiveCase.selected_providers("unknown-secret-sentinel")
    end
  end

  test "Discord resolves every Telegram baseline ID and runs each eligible body or reports a reason" do
    baseline = LiveCase.Baseline.ids()
    discord = DiscordFixture.cases()
    by_id = Map.new(discord, &{&1.id, &1})
    assert Enum.take(Enum.map(discord, & &1.id), length(baseline)) == baseline
    assert map_size(by_id) == length(discord)
    assert Enum.map(LiveFixture.cases(), & &1.id) == baseline ++ ["A17-LIVE"]
    unsupported = ~w(P03 P05 P06 P07 A03 A05 A06 A08 A15)

    for id <- baseline do
      spec = Map.fetch!(by_id, id)

      if id in unsupported do
        assert {:unsupported, reason} = LiveCase.support(DiscordFixture, spec)
        assert byte_size(reason) > 0
      else
        assert :ready = LiveCase.support(DiscordFixture, spec)
        assert {module, function} = spec.body
        assert Code.ensure_loaded?(module)
        assert function_exported?(module, function, 1)
      end
    end

    env(@selector, "discord")
    env("RUN_LIVE_DISCORD_TESTS", "true")
    env("RUN_LIVE_DISCORD_UI", nil)
    assert :ready = LiveCase.eligibility(DiscordFixture, by_id["P01"], :shared)
    assert {:inactive, _} = LiveCase.eligibility(DiscordFixture, by_id["P01"], :legacy)
    assert {:unsupported, _} = LiveCase.eligibility(DiscordFixture, by_id["P03"], :shared)
    refute LiveCase.selected?(LiveFixture, :shared)
  end

  test "real interaction delivery requires a second opt-in for each provider" do
    env(@selector, "telegram,discord")

    for {profile, flag} <- [{LiveFixture, @manual}, {DiscordFixture, "RUN_LIVE_DISCORD_UI"}] do
      env(flag, nil)
      by_id = Map.new(profile.cases(), &{&1.id, &1})
      manual = by_id["A17-LIVE"]
      reason = "set #{flag}=true"

      assert :ready = LiveCase.eligibility(profile, by_id["A17"], :shared)
      assert {:inactive, ^reason} = LiveCase.eligibility(profile, manual, :shared)

      assert_raise ExUnit.AssertionError, ~r/live check inactive: #{reason}/, fn ->
        LiveCase.run(profile, manual, :atomics.new(1, []), :shared)
      end

      System.put_env(flag, "true")
      assert :ready = LiveCase.eligibility(profile, manual, :shared)
    end
  end

  test "all 38 Telegram slots have a callable body and their declared requirements are available" do
    cases = LiveFixture.cases()
    expected_ids = Enum.map(1..21, &case_id("P", &1)) ++ Enum.map(1..17, &case_id("A", &1))
    assert Enum.map(cases, & &1.id) == expected_ids ++ ["A17-LIVE"]

    for %{body: {module, function}} = spec <- cases do
      assert Code.ensure_loaded?(module)
      assert function_exported?(module, function, 1)
      assert :ready = LiveCase.support(LiveFixture, spec)
    end

    env(@selector, "telegram")
    unsupported = %{case_spec("P01") | operations: [:fetch_messages]}
    assert {:unsupported, "operation :fetch_messages"} = LiveCase.support(LiveFixture, unsupported)

    assert_raise ExUnit.AssertionError, ~r/live check unsupported: operation :fetch_messages/, fn ->
      LiveCase.run(LiveFixture, unsupported, :atomics.new(1, []), :shared)
    end

    assert {:unsupported, "feature :unknown_feature"} =
             LiveCase.support(LiveFixture, %{case_spec("P01") | features: [:unknown_feature]})
  end

  test "missing credentials and a missing forum are setup blockers" do
    env(@selector, "telegram")
    env("TELEGRAM_BOT_TOKEN", nil)
    env("TELEGRAM_TEST_FORUM_CHAT_ID", nil)
    stop = :atomics.new(1, [])

    assert_raise ExUnit.AssertionError, ~r/live setup blocked: set TELEGRAM_BOT_TOKEN/, fn ->
      LiveCase.run(LiveFixture, case_spec("P01"), stop, :shared)
    end

    System.put_env("TELEGRAM_BOT_TOKEN", "local-credential-sentinel")

    assert_raise ExUnit.AssertionError, ~r/live setup blocked: set TELEGRAM_TEST_FORUM_CHAT_ID to a test forum/, fn ->
      LiveCase.run(LiveFixture, case_spec("P17"), stop, :shared)
    end

    refute_received {:telegram_live_wire, _, _, _}
  end

  test "an uncertain write stops later remote cases before preparation" do
    env(@selector, "telegram")
    stop = :atomics.new(1, [])
    assert :ok = LiveCase.halt(stop, :uncertain_write)

    assert_raise ExUnit.AssertionError, ~r/live setup blocked: a provider write has an uncertain outcome/, fn ->
      LiveCase.run(LiveFixture, case_spec("P01"), stop, :shared)
    end

    assert LiveCase.cleanup_allowed?(stop)
    assert :ok = LiveCase.halt(stop, :rate_limited)
    refute LiveCase.cleanup_allowed?(stop)
  end

  test "a typed unknown failure disallows more writes without printing the failed signal" do
    stop = :atomics.new(1, [])

    failed = %Jido.Signal{
      type: "jido.chat.test.failed",
      source: "jido:chat:test",
      id: "local",
      data: %{"outcome" => "unknown", "private" => "private-signal-sentinel"}
    }

    result = {:error, %Jido.Chat.Error{signal: failed}}

    error =
      assert_raise ExUnit.AssertionError, fn ->
        LiveCase.protect(fn -> assert {:ok, _} = result end, stop)
      end

    assert LiveCase.halted?(stop)
    assert LiveCase.failure_reason(stop) == "a provider write has an uncertain outcome"
    refute inspect(error) =~ "private-signal-sentinel"
  end

  test "Telegram keeps known message IDs and pending writes when the caller is killed" do
    {:ok, tracker} = Tracker.start()
    on_exit(fn -> Agent.stop(tracker) end)
    owner = self()

    opts = [
      live_wire?: true,
      live_stop: :atomics.new(1, []),
      live_observer: owner,
      live_tracker: tracker,
      ex_gram_module: FixtureBot
    ]

    {pid, monitor} =
      spawn_monitor(fn ->
        {:ok, _} =
          LiveFixture.Transport.call(
            "local-sentinel",
            "sendMessage",
            %{"chat_id" => "123", "text" => "local only"},
            opts
          )

        :ok = Tracker.begin_write(tracker)
        send(owner, :write_pending)

        receive do
          :finish -> :ok
        end
      end)

    assert_receive {:telegram_live_wire, "sendMessage", _, {:ok, %{"message_id" => 42}}}
    assert_receive :write_pending
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}

    assert %{messages: messages, pending: 1} = Tracker.close(tracker)
    assert MapSet.to_list(messages) == [{"123", "42"}]
    assert :closed = Tracker.begin_write(tracker)
  end

  test "assertions and transport exceptions cannot print private values" do
    error =
      assert_raise ExUnit.AssertionError, fn ->
        LiveCase.protect(fn ->
          require Logger
          Logger.error("credential-log-sentinel")
          raise "credential-error-sentinel"
        end)
      end

    assert Exception.message(error) =~ "live check failed (RuntimeError)"
    refute inspect(error) =~ "credential-error-sentinel"
  end

  test "pure cases pass without credential or provider I/O" do
    env(@selector, "telegram")
    env("TELEGRAM_BOT_TOKEN", nil)
    stop = :atomics.new(1, [])
    LiveCase.run(LiveFixture, case_spec("P11"), stop, :shared)
    LiveCase.run(LiveFixture, case_spec("P19"), stop, :shared)
    refute_received {:telegram_live_wire, _, _, _}
  end

  test "portable send uses Jido.Chat and checks the Telegram witness" do
    assert :ok = LiveCase.Probes.send_text(offline_context())
  end

  test "portable send fails when the Telegram request differs from the completed signal" do
    ctx = offline_context()
    ctx = put_in(ctx.client.config, Keyword.put(ctx.client.config, :mismatched_witness?, true))

    assert_raise ExUnit.AssertionError, fn ->
      LiveCase.Probes.send_text(ctx)
    end
  end

  test "the topic baseline has a positive forum branch and a negative private branch" do
    ctx = offline_context()

    LiveFixture.cases()
    |> Enum.find(&(&1.id == "A16"))
    |> then(fn %{body: {module, function}} ->
      apply(module, function, [%{ctx | forum_id: "-123"}])
      apply(module, function, [ctx])
    end)

    assert_received {:telegram_live_wire, "createForumTopic", %{"chat_id" => "-123"}, {:ok, _}}
  end

  defp offline_context do
    {:ok, ctx} = LiveFixture.prepare(case_spec("P11"), "local", :atomics.new(1, []))
    %{ctx | client: %{ctx.client | transport: FixtureTransport}, keep_messages?: false}
  end

  defp case_spec(id), do: Enum.find(LiveFixture.cases(), &(&1.id == id))
  defp case_id(prefix, number), do: prefix <> String.pad_leading(Integer.to_string(number), 2, "0")

  defp env(name, value) do
    old = System.get_env(name)
    on_exit(fn -> put_env(name, old) end)
    put_env(name, value)
  end

  defp put_env(name, nil), do: System.delete_env(name)
  defp put_env(name, value), do: System.put_env(name, value)
end
